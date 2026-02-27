class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.icon,
  });

  final String id;
  final String name;
  final String icon;
}

const defaultCategories = <ExpenseCategory>[
  ExpenseCategory(id: 'groceries', name: 'Groceries', icon: '🛒'),
  ExpenseCategory(id: 'restaurants', name: 'Restaurants', icon: '🍽️'),
  ExpenseCategory(id: 'shopping', name: 'Shopping', icon: '🛍️'),
  ExpenseCategory(id: 'transportation', name: 'Transportation', icon: '🚗'),
  ExpenseCategory(id: 'entertainment', name: 'Entertainment', icon: '🎬'),
  ExpenseCategory(id: 'subscriptions', name: 'Subscriptions', icon: '📱'),
  ExpenseCategory(id: 'utilities', name: 'Utilities', icon: '💡'),
  ExpenseCategory(id: 'healthcare', name: 'Healthcare', icon: '🏥'),
  ExpenseCategory(id: 'travel', name: 'Travel', icon: '✈️'),
  ExpenseCategory(id: 'education', name: 'Education', icon: '📚'),
  ExpenseCategory(id: 'personal', name: 'Personal Care', icon: '💆'),
  ExpenseCategory(id: 'other', name: 'Other', icon: '📦'),
];

ExpenseCategory categoryById(String? id) {
  return defaultCategories.firstWhere(
    (category) => category.id == id,
    orElse: () => defaultCategories.last,
  );
}
