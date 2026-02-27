# ReceiptNest Mobile

Flutter mobile app for ReceiptNest.

## Local Setup

1. Install dependencies:
```bash
flutter pub get
```
2. Generate Firebase config (required, files are intentionally gitignored):
```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=receipt-nest
```
3. iOS only:
```bash
cd ios && pod install --repo-update && cd ..
```
4. Run:
```bash
flutter run
```

## Security Note

This repo ignores local/secret config files including:
- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `macos/Runner/GoogleService-Info.plist`
- `.env*`
- Android signing keys / keystore files
