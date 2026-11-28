/// System-generated picker filenames are useful for storage, but not for people.
/// Keep original names intact and use this only when presenting a file label.
String receiptFileLabel(String? originalName, {int? receiptNumber}) {
  final name = originalName?.trim() ?? '';
  if (name.isEmpty) {
    return receiptNumber == null ? 'Your receipt' : 'Receipt $receiptNumber';
  }
  final generated =
      name.toLowerCase().startsWith('image_picker') ||
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?:\.[^.]+)?$',
        caseSensitive: false,
      ).hasMatch(name);
  if (!generated) return name;
  if (receiptNumber != null) return 'Receipt $receiptNumber';
  final image = const {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  }.contains(name.split('.').last.toLowerCase());
  return image ? 'Receipt photo' : 'Receipt document';
}
