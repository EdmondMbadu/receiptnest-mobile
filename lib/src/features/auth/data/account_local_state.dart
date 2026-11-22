import 'package:shared_preferences/shared_preferences.dart';

/// Remove this account's resumable tasks after confirmed account deletion.
/// Ordinary sign-out preserves them so an interrupted upload can be resumed.
Future<void> clearDeletedAccountLocalState(String uid) async {
  final preferences = await SharedPreferences.getInstance();
  for (final key in [
    'native_onboarding_v2:$uid',
    'native_onboarding_v2:$uid:pending',
    'native_onboarding_v2:$uid:count',
    'receipt_upload_activity_v1:$uid',
    'getting_started_prompt_v1:$uid',
  ]) {
    await preferences.remove(key);
  }
}
