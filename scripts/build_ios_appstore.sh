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

flutter build ipa --release "${dart_defines[@]}"
