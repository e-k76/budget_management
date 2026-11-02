import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

/// Dashboard data + permission-checked write operations.
class AppState extends ChangeNotifier {
  AppState(this._db, this._auth);

  final DatabaseService _db;
  final AuthService _auth;

  List<ProjectSummary> summaries = [];
  bool loading = false;
  String? loadError;

  AppUser get _user => _auth.currentUser!;

  double budgetPercentage = 100;
  Map<String, double> monthlyIncome = {};
  Map<String, double> monthlyExpense = {};

  List<Project> get projects => summaries.map((s) => s.project).toList();

  double get totalIncome => summaries.fold(0, (a, s) => a + s.income);
  double get totalBudget => summaries.fold(0, (a, s) => a + s.budgetedIncome);
  double get totalExpenses => summaries.fold(0, (a, s) => a + s.totalExpenses);
  double get totalApproved => summaries.fold(0, (a, s) => a + s.approvedExpenses);
  double get totalUnapproved => totalExpenses - totalApproved;
  /// درآمد کلی − هزینه کل تاییدشده
  double get netBalance => totalIncome - totalApproved;
  double get totalBalance => summaries.fold(0, (a, s) => a + s.balance);

  /// Tickets not yet done (shown as a badge for admins only).
  int openTickets = 0;

  /// [silent] = background reload (live sync): no loading state, no flicker.
  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      loading = true;
      loadError = null;
      notifyListeners();
    }
    try {
      summaries = await _db.getProjectSummaries();
      budgetPercentage = await _db.getBudgetPercentage();
      final monthly = await _db.getMonthlyTotals();
      monthlyIncome = monthly.$1;
      monthlyExpense = monthly.$2;
    } catch (e) {
      loadError = 'خطا در خواندن پایگاه داده: $e';
    }
    await _refreshTicketCount();
    loading = false;
    notifyListeners();
  }

  void clear() {
    openTickets = 0;
    summaries = [];
    loadError = null;
    notifyListeners();
  }

  void _requireEdit() {
    if (!_user.canEdit) throw AuthException('دسترسی کافی ندارید');
  }

  void _requireAdmin() {
    if (!_user.isAdmin) throw AuthException('دسترسی کافی ندارید');
  }

  Future<void> addProject(String name) async {
    _requireAdmin();
    final n = name.trim();
    if (n.isEmpty) throw AuthException('نام پروژه الزامی است');
    if (summaries.any((s) => s.name == n)) {
      throw AuthException('پروژه‌ای با این نام وجود دارد');
    }
    try {
      await _db.insertProject(n);
    } catch (_) {
      throw AuthException('پروژه‌ای با این نام وجود دارد');
    }
    await refresh();
  }

  Future<void> setBudgetPercentage(double pct) async {
    _requireEdit(); // admin or manager
    if (pct < 0 || pct > 1000) throw AuthException('درصد بودجه نامعتبر است');
    await _db.setBudgetPercentage(pct);
    await refresh();
  }

  Future<void> saveExpense(Expense e) async {
    _requireEdit();
    if (e.uid == null) {
      await _db.insertExpense(e, _user.fullName);
    } else {
      await _db.updateExpense(e);
    }
    await refresh();
  }

  Future<void> setApproval(Expense e, bool approved) async {
    _requireEdit();
    await _db.setExpenseApproval(e.uid!, approved, _user.fullName);
    await refresh();
  }

  Future<void> deleteExpense(Expense e) async {
    _requireEdit();
    await _db.deleteExpense(e.uid!);
    await refresh();
  }

  Future<void> addIncome(Income i) async {
    _requireEdit();
    await _db.addIncome(i, _user.fullName);
    await refresh();
  }

  Future<void> updateIncomeAmount(Income i, double amount) async {
    _requireEdit();
    await _db.updateIncomeAmount(i.uid!, amount);
    await refresh();
  }

  Future<void> deleteIncome(Income i) async {
    _requireAdmin();
    await _db.deleteIncome(i.uid!);
    await refresh();
  }

  // Read helpers used by the project details screen.
  Future<List<Expense>> expensesOf(String project) => _db.getExpenses(project);
  Future<List<Income>> incomesOf(String project) => _db.getIncomes(project);
  Future<List<Expense>> allExpenses() => _db.getAllExpenses();
  Future<List<Income>> allIncomes() => _db.getAllIncomes();

  // ---------------------------------------------------------------- tickets

  Future<void> _refreshTicketCount() async {
    try {
      openTickets =
          (_auth.currentUser?.isAdmin ?? false) ? await _db.countOpenTickets() : 0;
    } catch (_) {
      // a ticket count must never break loading the dashboard
    }
  }

  /// Any signed-in user may send a ticket.
  Future<void> submitTicket({
    required String kind,
    required String subject,
    required String message,
  }) async {
    final s = subject.trim(), m = message.trim();
    if (!Ticket.kinds.containsKey(kind)) throw AuthException('نوع تیکت نامعتبر است');
    if (s.isEmpty) throw AuthException('موضوع تیکت را وارد کنید');
    if (m.isEmpty) throw AuthException('متن تیکت را وارد کنید');
    if (s.length > Ticket.maxSubject) {
      throw AuthException('موضوع حداکثر ${Ticket.maxSubject} کاراکتر باشد');
    }
    if (m.length > Ticket.maxMessage) {
      throw AuthException('متن حداکثر ${Ticket.maxMessage} کاراکتر باشد');
    }
    final u = _user;
    await _db.insertTicket(
        kind: kind,
        subject: s,
        message: m,
        createdBy: u.username,
        createdByName: u.fullName);
    await _refreshTicketCount();
    notifyListeners();
  }

  /// Only admins can read tickets.
  Future<List<Ticket>> tickets() async {
    _requireAdmin();
    return _db.getTickets();
  }

  Future<void> setTicketStatus(Ticket t, String status) async {
    _requireAdmin();
    if (!Ticket.statuses.containsKey(status)) throw AuthException('وضعیت نامعتبر است');
    await _db.setTicketStatus(t.uid, status, _user.fullName);
    await _refreshTicketCount();
    notifyListeners();
  }

  Future<void> deleteTicket(Ticket t) async {
    _requireAdmin();
    await _db.deleteTicket(t.uid);
    await _refreshTicketCount();
    notifyListeners();
  }
}
