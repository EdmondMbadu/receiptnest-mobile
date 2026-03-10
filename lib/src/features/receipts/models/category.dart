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
  ExpenseCategory(id: 'restaurants', name: 'Restaurants & Dining', icon: '🍽️'),
  ExpenseCategory(id: 'shopping', name: 'Shopping', icon: '🛍️'),
  ExpenseCategory(id: 'transportation', name: 'Transportation', icon: '🚗'),
  ExpenseCategory(id: 'gas_fuel', name: 'Gas & Fuel', icon: '⛽'),
  ExpenseCategory(id: 'entertainment', name: 'Entertainment', icon: '🎬'),
  ExpenseCategory(id: 'subscriptions', name: 'Subscriptions', icon: '📱'),
  ExpenseCategory(id: 'utilities', name: 'Utilities & Bills', icon: '💡'),
  ExpenseCategory(id: 'healthcare', name: 'Healthcare', icon: '🏥'),
  ExpenseCategory(id: 'travel', name: 'Travel & Hotels', icon: '✈️'),
  ExpenseCategory(id: 'education', name: 'Education', icon: '📚'),
  ExpenseCategory(id: 'personal', name: 'Personal Care', icon: '💆'),
  ExpenseCategory(id: 'home_garden', name: 'Home & Garden', icon: '🏠'),
  ExpenseCategory(id: 'clothing', name: 'Clothing & Apparel', icon: '👗'),
  ExpenseCategory(id: 'gifts_donations', name: 'Gifts & Donations', icon: '🎁'),
  ExpenseCategory(id: 'pets', name: 'Pets', icon: '🐾'),
  ExpenseCategory(id: 'fitness', name: 'Fitness & Sports', icon: '💪'),
  ExpenseCategory(id: 'other', name: 'Other', icon: '📦'),
];

ExpenseCategory categoryById(String? id) {
  return defaultCategories.firstWhere(
    (category) => category.id == id,
    orElse: () => defaultCategories.last,
  );
}
