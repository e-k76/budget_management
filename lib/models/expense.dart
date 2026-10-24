class Expense {
  final int? id;
  final String projectName;
  final String date;
  final double amount;
  final double percentage;
  final String description;
  final bool isApproved;
  final String? approvedBy;
  final String? createdBy;

  const Expense({
    this.id,
    required this.projectName,
    required this.date,
    required this.amount,
    this.percentage = 0,
    this.description = '',
    this.isApproved = false,
    this.approvedBy,
    this.createdBy,
  });

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as int?,
        projectName: m['project_name'] as String,
        date: m['date'] as String,
        amount: (m['amount'] as num).toDouble(),
        percentage: (m['percentage'] as num?)?.toDouble() ?? 0,
        description: (m['description'] as String?) ?? '',
        isApproved: (m['is_approved'] as int? ?? 0) == 1,
        approvedBy: m['approved_by'] as String?,
        createdBy: m['created_by'] as String?,
      );
}
