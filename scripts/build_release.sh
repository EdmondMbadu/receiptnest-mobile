#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

app_version="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
release_dir="${RECEIPTNEST_RELEASE_DIR:-output/releases/${app_version}-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$release_dir"
release_dir="$(cd "$release_dir" && pwd)"
export RECEIPTNEST_RELEASE_DIR="$release_dir"

if [[ ! -f android/key.properties ]]; then
  echo 'Android release signing is missing: android/key.properties.' >&2
  exit 64
fi

# Shared Flutter arguments, such as --build-number, are forwarded to every build.
flutter analyze --no-pub
flutter test --no-pub

scripts/build_ios_appstore.sh "$@"
mkdir -p "$release_dir/ios"
shopt -s nullglob
archives=(build/ios/archive/*.xcarchive)
ipas=(build/ios/ipa/*.ipa)
if [[ ${#archives[@]} -ne 1 || ${#ipas[@]} -ne 1 ]]; then
  echo 'Expected one fresh iOS archive and IPA; inspect build/ios before proceeding.' >&2
  exit 1
fi
ditto "${archives[0]}" "$release_dir/ios/ReceiptNest.xcarchive"
cp "${ipas[0]}" "$release_dir/ios/ReceiptNest.ipa"

# Development exports estimate per-device sizes without uploading anything.
# This step is optional: some signing setups have only a distribution profile.
python3 - "$release_dir" ios/Runner.xcodeproj/project.pbxproj <<'PY'
import plistlib, re, sys
from pathlib import Path
release, project = map(Path, sys.argv[1:])
team = re.search(r'DEVELOPMENT_TEAM = ([A-Z0-9]+);', project.read_text())
options = {
    'method': 'debugging',
    'destination': 'export',
    'signingStyle': 'automatic',
    'stripSwiftSymbols': True,
    'thinning': '<thin-for-all-variants>',
}
if team:
    options['teamID'] = team[1]
(release / 'ios/development-export-options.plist').write_bytes(plistlib.dumps(options))
PY
if ! xcodebuild -exportArchive \
  -archivePath "$release_dir/ios/ReceiptNest.xcarchive" \
  -exportPath "$release_dir/ios/development" \
  -exportOptionsPlist "$release_dir/ios/development-export-options.plist" \
  > "$release_dir/ios/development-export.log" 2>&1; then
  echo "Development size report unavailable; see $release_dir/ios/development-export.log."
fi

mkdir -p "$release_dir/android" "$release_dir/symbols/android-aab" "$release_dir/symbols/android-apk"
flutter build appbundle --release \
  --split-debug-info="$release_dir/symbols/android-aab" "$@"
cp build/app/outputs/bundle/release/app-release.aab "$release_dir/android/ReceiptNest.aab"
if [[ -d build/app/outputs/mapping/release ]]; then
  ditto build/app/outputs/mapping/release "$release_dir/symbols/android-aab/r8"
fi

flutter build apk --release --split-per-abi \
  --split-debug-info="$release_dir/symbols/android-apk" "$@"
for abi in armeabi-v7a arm64-v8a x86_64; do
  cp "build/app/outputs/flutter-apk/app-$abi-release.apk" "$release_dir/android/ReceiptNest-$abi.apk"
done
if [[ -d build/app/outputs/mapping/release ]]; then
  ditto build/app/outputs/mapping/release "$release_dir/symbols/android-apk/r8"
fi

python3 scripts/report_release_sizes.py "$release_dir"
echo "Release artifacts and crash symbols: $release_dir"
