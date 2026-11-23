#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Source local production env if it exists. Real values live there (gitignored).
if [[ -f ".env.production" ]]; then
  set -a
  # shellcheck disable=SC1091
  source ".env.production"
  set +a
fi

if [[ -z "${REVENUECAT_IOS_API_KEY:-}" ]]; then
  cat >&2 <<'EOF'
Missing REVENUECAT_IOS_API_KEY.

Either:
  1. Copy .env.production.example to .env.production and fill in real values, or
  2. Run with the env var inline:

REVENUECAT_IOS_API_KEY=appl_your_public_ios_key scripts/build_ios_appstore.sh

Get the iOS public SDK key from:
RevenueCat Dashboard -> Project Settings -> API keys -> App-specific public SDK key for iOS
EOF
  exit 64
fi

if [[ "${REVENUECAT_IOS_API_KEY}" != appl_* ]]; then
  echo "REVENUECAT_IOS_API_KEY should be the iOS public SDK key and usually starts with appl_." >&2
  exit 64
fi

dart_defines=(
  "--dart-define=REVENUECAT_IOS_API_KEY=${REVENUECAT_IOS_API_KEY}"
  "--dart-define=REVENUECAT_PRO_ENTITLEMENT_ID=${REVENUECAT_PRO_ENTITLEMENT_ID:-pro}"
)

if [[ -n "${REVENUECAT_IOS_OFFERING_ID:-}" ]]; then
  dart_defines+=("--dart-define=REVENUECAT_IOS_OFFERING_ID=${REVENUECAT_IOS_OFFERING_ID}")
fi

if [[ -n "${REVENUECAT_IOS_MONTHLY_PACKAGE_ID:-}" ]]; then
  dart_defines+=("--dart-define=REVENUECAT_IOS_MONTHLY_PACKAGE_ID=${REVENUECAT_IOS_MONTHLY_PACKAGE_ID}")
fi

if [[ -n "${REVENUECAT_IOS_ANNUAL_PACKAGE_ID:-}" ]]; then
  dart_defines+=("--dart-define=REVENUECAT_IOS_ANNUAL_PACKAGE_ID=${REVENUECAT_IOS_ANNUAL_PACKAGE_ID}")
fi

# Keep symbols outside the app and retain them alongside this build's artifacts.
release_dir="${RECEIPTNEST_RELEASE_DIR:-output/releases/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$release_dir/symbols/ios"
if [[ -d build/ios/ipa ]]; then
  # An old IPA must not be mistaken for a successful export of this build.
  mkdir -p output/previous-ios-exports
  previous_exports="output/previous-ios-exports/$(date -u +%Y%m%dT%H%M%SZ)"
  mv build/ios/ipa "$previous_exports"
fi
flutter build ipa --release \
  --split-debug-info="$release_dir/symbols/ios" \
  "${dart_defines[@]}" "$@"
shopt -s nullglob
ipas=(build/ios/ipa/*.ipa)
if [[ ${#ipas[@]} -ne 1 ]]; then
  echo 'The archive was built, but no fresh IPA was exported. Check the signing/export errors above.' >&2
  exit 1
fi
