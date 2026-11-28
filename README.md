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
4. Run iOS with the billing configuration from `.env.development` (when present) or `.env.production`:
```bash
scripts/run_ios.sh -d <device-id>
```

Use `.env.production.example` as the configuration template. The launcher passes the RevenueCat public SDK key and offering settings as Dart compile-time defines. A plain `flutter run` does not load these files and leaves App Store billing unconfigured.

For an App Store or TestFlight archive, use `scripts/build_ios_appstore.sh`. It loads `.env.production` and stops before building if the iOS public SDK key is missing. Validate subscription loading, purchase, and restore in TestFlight before submitting a release.

For other platforms, use `flutter run -d <device-id>`.

## Optimized release builds

Run `scripts/build_release.sh --no-pub` to validate and build a signed iOS IPA/archive, a Google Play AAB, and separate Android APKs for ARM32, ARM64, and x86-64. Shared Flutter arguments such as `--build-number=10` are forwarded to each build; choose an unused build number before uploading. The iOS build loads the production RevenueCat configuration as above.

Each run saves its artifacts, Dart symbols, Android R8 mappings, native iOS dSYMs (inside the archive), and `sizes.json` under a dated `output/releases/` directory. Preserve the complete directory with each distributed build so crash traces can be symbolicated. The default iOS export also includes native symbols for App Store processing. Do not compare the entire IPA or AAB upload size with a user's download size.

When a development signing profile is available, the same archive is also exported locally with device thinning to generate `App Thinning Size Report.txt`. This is a development estimate; App Store Connect and Google Play provide the final delivery sizes. Nothing in these scripts uploads or publishes a build. Rebuild after further source changes before distributing the next testing or store release.

## Security Note

This repo ignores local/secret config files including:
- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `macos/Runner/GoogleService-Info.plist`
- `.env*`
- Android signing keys / keystore files

## Help & getting started

The Help page offers one guided action and three short, expandable topics: finding or editing receipts, email forwarding, and exports. Only one answer opens at a time, with a link to the relevant app screen. The captioned video and support remain secondary links. The layout supports both themes and scrolls naturally with enlarged text.

## Insights

- Pro Insights starts with a question box and two optional example questions. Saved conversations open from History; the page does not automatically load a long previous thread. New question starts a separate conversation, and sharing is available from the conversation menu.
- The app shell handles keyboard layout once and keeps Home, Insights, and Collections above the keyboard. Introductory prompts recede while typing. Drafts, the current conversation, scroll position, and pending answers survive tab changes within the same account/session; changing accounts clears that state.

## Email receipts

- Forward an email is available when choosing a receipt source in the first-receipt guide, in the Add Receipt sheet, and in Settings. The empty Home screen keeps the focus on Add my first receipt. All forwarding entry points open the same instructions and account-specific address; the existing backend allocates addresses without requiring a prior receipt. Existing addresses are reused.
- Copying the address does not complete onboarding or claim a receipt arrived. New email receipts appear in the existing receipt activity and result flow, with their original purchase month and review requirements. The guide can continue with the received receipt.
- The first receipt snapshot is a baseline, so historical emails do not trigger arrival notices. Copying saves a short-lived, account-specific checkpoint containing only a timestamp and receipt IDs, allowing arrival recovery after restarting the app. Confirmed account deletion clears that checkpoint.
- Messages render lazily, and a new answer keeps the reader near its beginning. Follow-up requests send the most recent ten messages as context while preserving the full saved conversation.
- Regression coverage includes keyboard navigation, small screens, landscape, enlarged text, late responses, account changes, failed requests, and history selection. Existing release artifacts must be rebuilt after these source changes before distribution.

## Original receipt viewer

- Photos and PDFs open directly in the app, with one inline preview and a full-screen viewer. Tapping the preview or its single expand button opens the same viewer; duplicate file cards and generated filename labels are omitted, while meaningful document names remain visible. PDF pages use the platform's native renderer through `pdfx`; receipt viewing does not use a WebView or a hosted Google document viewer.
- Originals are downloaded directly from Firebase Storage under the current account. The inline and full-screen views share an in-memory download, released when both close. Decoded images and PDF pages have bounded dimensions, and PDFs render one page at a time.
- Full-screen viewing supports pinch and double-tap zoom, fit-to-screen, and previous/next PDF pages. Download and renderer failures offer retry. Other document types retain a clearly labeled original-file fallback.
- Native cleanup waits for page rendering before closing the document, including when navigating away or switching accounts. Preview tests cover painted image pixels, page navigation, retry, empty files, account isolation, and late native responses.

## Getting started and welcome email

- Verified sign-in triggers the shared `sendWelcomeEmail` callable, which links to the captioned walkthrough at https://receipt-nest.com/getting-started#walkthrough. The backend's existing sent flag prevents repeat welcomes across sessions.
- App startup/resume checks for email verification and retries failed welcome delivery without blocking app access. Repeated auth events are coalesced per account.
- **Help & getting started** is always available in the drawer. The native help page includes accurate mobile instructions, the public video link, and the actual upload sheet.
- Native onboarding v2 automatically introduces every account with 0–4 receipts, including accounts that completed the web tour or dismissed the old mobile card. The account-wide server count controls eligibility; 5+ accounts open Home normally.
- The guided task follows Add → Organize → View through a real upload. Confirmed receipt deletion clears only an unfinished task’s reference; completed onboarding and activation history are preserved. Deleted receipts recover to source choices, while connection errors retain progress for retry. Missing Firestore cache entries and optimistic deletions with pending writes are never treated as confirmed deletions. Progress is account-scoped, with a durable local outbox for offline recovery. Choosing “later” pauses the guide; Home and Help let users resume. Completed guides can be replayed without resetting completion.
- Empty Home prioritizes adding a receipt, and both its main action and + button start a fresh guided upload. Accounts with 1–2 receipts see the newest upload first regardless of its receipt date; this featured section ends at three receipts. An unfinished guide has a small resume link below the receipt. Completed guides have no encouragement card, and old highlight URLs cannot keep a receipt pinned. The exact receipt is watched live through processing and review.
- Apple/Google appear before the expandable email form. Email verification returns to the same onboarding entry. The app requests camera access when the camera is chosen.
- Upload retries reuse a receipt ID and storage path, preventing duplicate records after a lost acknowledgement. Receipt details require a valid merchant, amount (including zero or a refund), and date before confirmation.
- Run `flutter analyze --no-pub` and `flutter test --no-pub`. The visual flow tests regenerate `output/onboarding/` previews, including light/dark, compact phone, large text, processing, ready, and success states.
- The shared backend lives in `../receipt-nest/functions`: `native-onboarding.ts`, `native-onboarding-policy.ts`, and `test/native-onboarding.test.cjs`. Release only `getNativeOnboardingState`, `saveNativeOnboardingProgress`, and `recordNativeReceiptActivation`. No Firestore rule change is required; the server writes a separate `users/{uid}.nativeOnboarding` map. The web’s `gettingStarted` state and email lifecycle are preserved.
- The three additive native backend functions were deployed to `receipt-nest/us-central1` on 2026-11-22. Readiness checks verified both callable endpoints reject unsigned requests (HTTP 401). The fallback count endpoint and local checkpoints also support UI testing against an older backend.
- Product Analytics events cover account access, source selection, upload acceptance/errors, processing results, usable receipt viewing, guide exposure and completion. Receipt contents, email addresses, filenames, and amounts are excluded. iOS Analytics uses the Core pod without advertising-ID capability; Android advertising-ID collection and ad-personalization signals are disabled. Confirm Google Analytics is enabled for the Firebase project before relying on GA event reports.
- The read-only backend report is `node scripts/report-native-onboarding.cjs --project=receipt-nest` (from the functions directory, with Application Default Credentials). It reports saved-and-viewed within 24 hours and three usable receipts within 14 days, requires complete observation windows, and separates new accounts, existing zero-receipt accounts, and accounts starting with 1–4 receipts. “New account” means account creation within 24 hours before first native use; unknown creation dates are reported separately. Permanent milestones survive later receipt deletion.
- Validation on 2026-11-22: `flutter analyze --no-pub` clean; all 44 Flutter tests and 17 focused native/web onboarding backend tests passed. The iOS simulator app was built and launched for manual testing; the Android debug APK also built successfully.
- These changes are not yet in the store releases. Release the updated mobile build through the normal signing, version/build-number, TestFlight/Play testing, and store submission process. No signing settings or app version were changed here.

## Receipt upload feedback

- Every accepted upload now has a live result sheet. Users can continue browsing while the exact receipt is processed, then reopen its activity bar above the navigation. Pending references survive app restarts and stay isolated to their account. Completed activity clears after acknowledgement; it does not permanently pin a receipt above the graph. Reopening activity always follows the selected receipt ID, including restored uploads from onboarding; it never restarts the guide.
- The first-receipt guide and repeat uploads share the result card: merchant, amount, transaction date, category, and explicit filing month. Only the **View month** action changes the dashboard period. Missing or uncertain fields lead to review; a missing transaction date is never presented as the upload date.
- Transfer progress reflects uploaded bytes. The saved state waits for the receipt write to be acknowledged. Independent preflight reads run concurrently, and the confirmed save returns its known receipt identity without an additional fetch. Retry IDs, original files, free-plan checks, extraction, and server validation are preserved. No receipt-processing backend deployment is needed for this update.
- Repeat uploads support multi-selection directly in the native Gallery and Files pickers. Camera adds one photo at a time. The same sheet holds removable previews, and its upload action stays outside the scrolling selection list. A single selected file retains the existing transfer and exact-receipt result; onboarding remains focused on one receipt.
- Batches save files in order using the existing repository and server plan checks. Every accepted file starts normal extraction immediately and enters account-scoped upload activity. Each batch row follows its exact receipt. One thin horizontal loading bar sits above the batch list while receipts are being read, with a live ready count and quiet text-only rows. Reduced motion uses a static line, and connection errors stop the loading bar. Processing rows offer View progress; finished rows show merchant, amount, and transaction date and open the exact receipt directly with View receipt or Review receipt. Continue browsing, tapping outside, and swiping down close the saved-upload sheet while receipts keep processing, and activity preserves access to their results. Outside taps, swipe dismissal, and back navigation stay blocked during actual file transfer; the native drag handle returns when it is safe to close. Generated picker names use readable display labels; stored filenames and upload identities remain unchanged. Validation errors and upload failures stay attached to their files; retries reuse only unsaved files’ original IDs. A free-plan limit stops further attempts and keeps the remaining selection available. Multiple receipts within one document are still a backend concern; this client change does not split files.
- `test/receipt_batch_upload_test.dart` covers native multi-selection, appended camera photos, cancellation, removal back to one file, per-file validation, partial failures and stable retry IDs, plan limits, live result navigation, account changes during transfers/picking, and 25-file lists at large text sizes in both themes. Preview screenshots regenerate under `output/upload/batch-*.png`.
- Upload analytics record elapsed, first-progress, and transfer-complete timings, plus file kind. Receipt contents, names, amounts, and filenames are excluded from those timing events. A read-only sample of 10 existing model calls showed a median round trip of 3.76 seconds; extraction is not instantaneous. There are no minimum display delays or simulated processing stages.
- Validation: 74 Flutter tests cover onboarding, upload/reading/results, earlier-month navigation, missing fields, retries, connection failures, deletion, pending-upload restoration, multiple uploads, account changes, large text, and exact-receipt navigation. Screenshots regenerate under `output/upload/` and `output/onboarding/`. The line-chart widgets, painter, and chart-data preparation are unchanged.
