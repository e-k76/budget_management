class Income {
  final int? id;
  final String projectName;
  final double amount;
  final String date;
  final String? createdBy;

  const Income({this.id, required this.projectName, required this.amount, required this.date, this.createdBy});

  factory Income.fromMap(Map<String, Object?> m) => Income(
        id: m['id'] as int?,
        projectName: m['project_name'] as String,
        amount: (m['amount'] as num).toDouble(),
        date: (m['date'] as String?) ?? '',
        createdBy: m['created_by'] as String?,
      );
}
