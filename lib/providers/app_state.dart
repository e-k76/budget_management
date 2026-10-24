import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../models/project.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/pending_queue.dart';

class AppState extends ChangeNotifier {
  final DatabaseService db = DatabaseService.instance;
  late final AuthService auth = AuthService(db);

  AppUser? user;
  List<Project> projects = [];

  bool get isAdmin => user?.isAdmin ?? false;
  bool get canEdit => user?.canEdit ?? false;
  String get _who => user?.fullName ?? '';

  double get totalIncome => projects.fold(0, (a, p) => a + p.totalIncome);
  double get totalExpenses => projects.fold(0, (a, p) => a + p.totalExpenses);
  double get remaining => totalIncome - totalExpenses;
  double get netBalance => projects.fold(0, (a, p) => a + p.balance);

  void _require(bool ok) {
    if (!ok) throw StateError('شما مجوز انجام این عملیات را ندارید');
  }

  Future<bool> login(String username, String password) async {
    final u = await auth.login(username, password);
    if (u == null) return false;
    user = u;
    await queue.load();
    await refresh();
    _startPolling();
    return true;
  }

  /// Bumped on every reload so open screens (e.g. project details) re-query.
  int revision = 0;
  Timer? _poller;
  int? _seenVersion;
  bool _polling = false;

  // ---- save-and-retry ----
  final PendingQueue queue = PendingQueue();
  bool online = true;
  String? syncNotice; // set when a queued change was rejected on replay
  int get pendingCount => queue.length;
  Future<void>? _flushLock; // tail of the serialized flush chain (created lazily)
  final Map<String, Object> _errors = {};
  String? _interactiveId;

  void clearNotice() {
    syncNotice = null;
    notifyListeners();
  }

  void _setOnline(bool v) {
    if (online == v) return;
    online = v;
    notifyListeners();
  }

  /// Persist the change locally FIRST (so it can never be lost), then try to send it.
  /// If the shared DB is unreachable it stays queued and is retried automatically.
  Future<void> _submit(bool allowed, String type, Map<String, Object?> data) async {
    _require(allowed);
    final op = PendingOp.create(type, data);
    await queue.add(op);
    if (!online) {
      notifyListeners(); // known offline: don't block the UI on a dead share; the poller retries
      return;
    }
    _interactiveId = op.id;
    await flushQueue();
    _interactiveId = null;
    final err = _errors.remove(op.id);
    if (err != null) throw err; // real rejection (e.g. duplicate name): show it to the user
  }

  /// Apply queued writes in order. Stops at the first connection failure.
  Future<void> flushQueue() {
    final prev = _flushLock;
    final run = prev == null ? _flushOnce() : prev.then((_) => _flushOnce());
    _flushLock = run.catchError((_) {});
    return run;
  }

  Future<void> _flushOnce() async {
    var applied = false;
    while (queue.length > 0) {
      final op = queue.ops.first;
      try {
        await db.apply(op);
        await queue.remove(op.id);
        applied = true;
        _setOnline(true);
      } catch (e) {
        if (isConnectionError(e)) {
          await db.reset();
          _setOnline(false);
          notifyListeners();
          return;
        }
        await queue.remove(op.id); // can never succeed: drop it, don't block the rest
        _errors[op.id] = e;
        if (op.id != _interactiveId) {
          syncNotice = 'یک تغییر ذخیره‌شده پس از اتصال رد شد: ${_msg(e)}';
        }
      }
    }
    notifyListeners();
    if (applied) {
      try {
        await refresh();
      } catch (_) {}
    }
  }

  static String _msg(Object e) => e.toString().replaceFirst('Bad state: ', '');

  /// Live sync: poll the DB's change counter; reload when another PC (or we) changed data.
  /// Also retries any queued changes and tracks whether the share is reachable.
  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_polling || user == null) return;
      _polling = true;
      try {
        if (queue.length > 0) await flushQueue();
        final v = await db.dataVersion();
        _setOnline(true);
        if (_seenVersion != null && v != _seenVersion) await refresh();
        _seenVersion = v;
      } catch (e) {
        if (isConnectionError(e)) {
          await db.reset();
          _setOnline(false);
        }
        // otherwise a transient hiccup: try again on the next tick
      } finally {
        _polling = false;
      }
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  void logout() {
    _poller?.cancel();
    _seenVersion = null;
    user = null;
    projects = [];
    notifyListeners();
  }

  Future<void> refresh() async {
    _seenVersion = await db.dataVersion();
    projects = await db.projects();
    revision++;
    notifyListeners();
  }

  // Projects
  Future<void> addProject(String name) => _submit(isAdmin, 'addProject', {'name': name});
  Future<void> setBudget(Project p, double pct) async {
    _require(isAdmin);
    await db.setBudgetPercentage(p.id, pct); // not queued: needs a live connection
    await refresh();
  }

  // Expenses
  Future<void> saveExpense(Expense e) => _submit(canEdit, e.id == null ? 'addExpense' : 'updateExpense', {
        'id': e.id,
        'project': e.projectName,
        'date': e.date,
        'amount': e.amount,
        'percentage': e.percentage,
        'description': e.description,
        'user': _who,
      });
  Future<void> deleteExpense(int id) => _submit(canEdit, 'deleteExpense', {'id': id});
  Future<void> setApproval(int id, bool v) => _submit(canEdit, 'setApproval', {'id': id, 'approved': v, 'user': _who});
  Future<List<Expense>> expensesOf(String project) => db.expenses(project);

  // Incomes
  Future<void> addIncome(String project, double amount, String date) =>
      _submit(canEdit, 'addIncome', {'project': project, 'amount': amount, 'date': date, 'user': _who});
  Future<void> updateIncome(int id, double amount, String date) =>
      _submit(canEdit, 'updateIncome', {'id': id, 'amount': amount, 'date': date});
  Future<void> deleteIncome(int id) => _submit(isAdmin, 'deleteIncome', {'id': id});
  Future<List<Income>> incomesOf(String project) => db.incomes(project);

  // Users
  Future<List<AppUser>> users() {
    _require(isAdmin);
    return db.users();
  }

  Future<void> createUser(String username, String password, String fullName, String role) {
    _require(isAdmin);
    return auth.createUser(username: username, password: password, fullName: fullName, role: role);
  }

  Future<void> deleteUser(int id) {
    _require(isAdmin && id != user?.id);
    return db.deleteUser(id);
  }

  @visibleForTesting
  Future<void> saveExpenseForTest() => saveExpense(const Expense(
      projectName: 'پروژه الف', date: '1404/01/12', amount: 500000, percentage: 10, description: 'تست'));
}
