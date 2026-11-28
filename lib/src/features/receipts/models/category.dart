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
  ExpenseCategory(id: 'money_transfers', name: 'Money transfers', icon: '💸'),
  ExpenseCategory(id: 'other', name: 'Other', icon: '📦'),
];

ExpenseCategory categoryById(String? id) {
  return defaultCategories.firstWhere(
    (category) => category.id == id,
    orElse: () => defaultCategories.last,
  );
}

/// Keep a saved category selectable even when an older app does not know it.
/// Editing another field must never silently reclassify the receipt as Other.
List<ExpenseCategory> categoryOptionsIncluding(
  String? savedId, {
  String? savedName,
}) {
  if (savedId == null ||
      defaultCategories.any((category) => category.id == savedId)) {
    return defaultCategories;
  }
  final words = savedId.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  final label = savedName?.trim();
  return [
    ...defaultCategories,
    ExpenseCategory(
      id: savedId,
      name: label != null && label.isNotEmpty
          ? label
          : words.isEmpty
          ? 'Uncategorized'
          : words[0].toUpperCase() + words.substring(1),
      icon: '📦',
    ),
  ];
}
