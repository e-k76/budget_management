class Project {
  final int id;
  final String name;
  final double budgetPercentage;
  final double totalIncome;
  final double totalExpenses;

  const Project({
    required this.id,
    required this.name,
    required this.budgetPercentage,
    required this.totalIncome,
    required this.totalExpenses,
  });

  factory Project.fromMap(Map<String, Object?> m) => Project(
        id: m['id'] as int,
        name: m['name'] as String,
        budgetPercentage: (m['budget_percentage'] as num?)?.toDouble() ?? 100,
        totalIncome: (m['total_income'] as num?)?.toDouble() ?? 0,
        totalExpenses: (m['total_expenses'] as num?)?.toDouble() ?? 0,
      );

  /// مانده هزینه
  double get remaining => totalIncome - totalExpenses;

  /// تراز کلی با احتساب درصد بودجه
  double get balance => totalIncome * budgetPercentage / 100 - totalExpenses;
}
