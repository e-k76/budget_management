import '../core/app_config.dart';

class AppUser {
  final int id;
  final String username;
  final String fullName;
  final String role;
  final String? createdAt;

  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.createdAt,
  });

  bool get isAdmin => role == Roles.admin;
  bool get canEdit => role == Roles.admin || role == Roles.manager;
  bool get canDelete => isAdmin;

  /// Expenses (not incomes) can also be deleted by managers.
  bool get canDeleteExpense => canEdit;

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: m['id'] as int,
        username: m['username'] as String,
        fullName: m['full_name'] as String,
        role: m['role'] as String,
        createdAt: m['created_at'] as String?,
      );
}

class Project {
  final int id;
  final String name;
  final double budgetPercentage;
  final double totalIncome;
  final String? createdAt;

  const Project({
    required this.id,
    required this.name,
    required this.budgetPercentage,
    required this.totalIncome,
    this.createdAt,
  });

  factory Project.fromMap(Map<String, Object?> m) => Project(
        id: m['id'] as int,
        name: m['name'] as String,
        budgetPercentage: (m['budget_percentage'] as num?)?.toDouble() ?? 100,
        totalIncome: (m['total_income'] as num?)?.toDouble() ?? 0,
        createdAt: m['created_at'] as String?,
      );
}

/// A project plus its aggregated expense figures.
class ProjectSummary {
  final Project project;
  final double totalExpenses;
  final double approvedExpenses;

  /// The single budget percentage shared by every project.
  final double budgetPercentage;

  const ProjectSummary({
    required this.project,
    required this.totalExpenses,
    required this.approvedExpenses,
    required this.budgetPercentage,
  });

  String get name => project.name;
  double get income => project.totalIncome;

  /// Expenses not yet approved (total minus approved).
  double get unapprovedExpenses => totalExpenses - approvedExpenses;

  /// Income minus all expenses (100% of income).
  double get remaining => income - totalExpenses;

  /// Income scaled by the global budget percentage.
  double get budgetedIncome => income * budgetPercentage / 100;

  /// تراز کلی: (درآمد × درصد بودجه) − مجموع هزینه‌های تاییدشده
  double get balance => budgetedIncome - approvedExpenses;

  factory ProjectSummary.fromMap(Map<String, Object?> m, double budgetPercentage) =>
      ProjectSummary(
        project: Project.fromMap(m),
        totalExpenses: (m['total_expenses'] as num?)?.toDouble() ?? 0,
        approvedExpenses: (m['approved_expenses'] as num?)?.toDouble() ?? 0,
        budgetPercentage: budgetPercentage,
      );
}

class Expense {
  final int? id;

  /// Stable identity shared by the local and remote databases.
  final String? uid;
  final String projectName;
  final String date;
  final double amount;
  final String payee;
  final String description;
  final bool isApproved;
  final String? approvedBy;

  /// Jalali date the expense was ticked as approved (تاریخ تایید).
  final String? approvedAt;
  final String? createdBy;
  final String? createdAt;

  const Expense({
    this.id,
    this.uid,
    required this.projectName,
    required this.date,
    required this.amount,
    this.payee = '',
    this.description = '',
    this.isApproved = false,
    this.approvedBy,
    this.approvedAt,
    this.createdBy,
    this.createdAt,
  });

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as int,
        uid: m['uid'] as String?,
        projectName: m['project_name'] as String,
        date: m['date'] as String,
        amount: (m['amount'] as num).toDouble(),
        payee: (m['payee'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        isApproved: ((m['is_approved'] as int?) ?? 0) == 1,
        approvedBy: m['approved_by'] as String?,
        approvedAt: m['approved_at'] as String?,
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at'] as String?,
      );
}

class Income {
  final int? id;
  final String? uid;
  final String projectName;
  final double amount;
  final String date;
  final String? createdBy;
  final String? createdAt;

  const Income({
    this.id,
    this.uid,
    required this.projectName,
    required this.amount,
    required this.date,
    this.createdBy,
    this.createdAt,
  });

  factory Income.fromMap(Map<String, Object?> m) => Income(
        id: m['id'] as int,
        uid: m['uid'] as String?,
        projectName: m['project_name'] as String,
        amount: (m['amount'] as num).toDouble(),
        date: m['date'] as String,
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at'] as String?,
      );
}


/// A support request (bug report / suggestion) any user can send; only admins read them.
class Ticket {
  const Ticket({
    this.id,
    required this.uid,
    required this.kind,
    required this.subject,
    required this.message,
    this.status = open,
    this.createdBy,
    this.createdByName,
    this.createdAt,
    this.updatedBy,
    this.updatedAt,
  });

  static const open = 'open';
  static const inProgress = 'in_progress';
  static const done = 'done';

  static const kinds = {
    'bug': 'گزارش خطا',
    'suggestion': 'پیشنهاد / قابلیت جدید',
    'other': 'سایر',
  };
  static const statuses = {
    open: 'جدید',
    inProgress: 'در حال بررسی',
    done: 'انجام شد',
  };
  static const maxSubject = 120;
  static const maxMessage = 4000;

  final int? id;

  /// Stable identity shared by the local and remote databases.
  final String uid;
  final String kind;
  final String subject;
  final String message;
  final String status;
  final String? createdBy; // username
  final String? createdByName; // full name when it was sent
  final String? createdAt;
  final String? updatedBy;
  final String? updatedAt;

  String get kindLabel => kinds[kind] ?? kind;
  String get statusLabel => statuses[status] ?? status;
  bool get isDone => status == done;

  factory Ticket.fromMap(Map<String, Object?> m) => Ticket(
        id: m['id'] as int?,
        uid: m['uid'] as String,
        kind: (m['kind'] as String?) ?? 'other',
        subject: (m['subject'] as String?) ?? '',
        message: (m['message'] as String?) ?? '',
        status: (m['status'] as String?) ?? open,
        createdBy: m['created_by'] as String?,
        createdByName: m['created_by_name'] as String?,
        createdAt: m['created_at'] as String?,
        updatedBy: m['updated_by'] as String?,
        updatedAt: m['updated_at'] as String?,
      );
}
