import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../models/project.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

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
    await refresh();
    return true;
  }

  void logout() {
    user = null;
    projects = [];
    notifyListeners();
  }

  Future<void> refresh() async {
    projects = await db.projects();
    notifyListeners();
  }

  Future<T> _write<T>(bool allowed, Future<T> Function() op) async {
    _require(allowed);
    final r = await op();
    await refresh();
    return r;
  }

  // Projects
  Future<void> addProject(String name) => _write(isAdmin, () => db.addProject(name));
  Future<void> setBudget(Project p, double pct) => _write(isAdmin, () => db.setBudgetPercentage(p.id, pct));

  // Expenses
  Future<void> saveExpense(Expense e) =>
      _write(canEdit, () => e.id == null ? db.addExpense(e, _who) : db.updateExpense(e));
  Future<void> deleteExpense(int id) => _write(isAdmin, () => db.deleteExpense(id));
  Future<void> setApproval(int id, bool v) => _write(canEdit, () => db.setApproval(id, v, _who));
  Future<List<Expense>> expensesOf(String project) => db.expenses(project);

  // Incomes
  Future<void> addIncome(String project, double amount, String date) =>
      _write(canEdit, () => db.addIncome(project, amount, date, _who));
  Future<void> updateIncome(int id, double amount, String date) =>
      _write(canEdit, () => db.updateIncome(id, amount, date));
  Future<void> deleteIncome(int id) => _write(isAdmin, () => db.deleteIncome(id));
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
