import 'package:intl/intl.dart';

final _currencyFormatter = NumberFormat.currency(symbol: r'$', decimalDigits: 2);

String formatCurrency(num? value) {
  if (value == null) return '-';
  return _currencyFormatter.format(value);
}

String formatDate(DateTime? value, {String pattern = 'MMM d, y'}) {
  if (value == null) return '-';
  return DateFormat(pattern).format(value);
}
