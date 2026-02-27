import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? asDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);

  if (value is Map<String, dynamic>) {
    final seconds = value['seconds'];
    final nanos = value['nanoseconds'];
    if (seconds is int && nanos is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        (seconds * 1000) + (nanos ~/ 1000000),
      );
    }
  }
  return null;
}

String sanitizeFileName(String name) {
  return name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
}
