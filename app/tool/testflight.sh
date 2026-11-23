#!/usr/bin/env bash
# Build the iPhone app at a release tag and upload it to TestFlight.
#
#   app/tool/testflight.sh            # HEAD must be exactly at an app-vX.Y.Z tag
#   app/tool/testflight.sh --dry-run  # build and sign for the App Store, no upload
#
# Runs on a Mac. Signing and the upload use an App Store Connect API key kept
# on this Mac, never in the repo or CI: ASC_KEY_ID and ASC_ISSUER_ID in the
# environment or in ~/.appstoreconnect/vouch.env, and the key itself at
# ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8. The identity comes
# from ios/Flutter/VouchLocal.xcconfig
# and the Firebase config from ios/Runner/GoogleService-Info.plist, as for
# any build. The build number is X*10000 + Y*100 + Z, as on Android, so each
# version uploads once. See README.md "iPhone releases (TestFlight)".
set -euo pipefail

cd "$(dirname "$0")/.."
DRY=false
[ "${1:-}" = "--dry-run" ] && DRY=true

TAG=$(git describe --tags --exact-match --match 'app-v*' HEAD 2>/dev/null || true)
if [ -z "$TAG" ]; then
  if $DRY; then
    TAG="app-v$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' pubspec.yaml)"
    echo "Dry run off a tag; using $TAG from pubspec.yaml."
  else
    echo "HEAD is not at an app-vX.Y.Z tag. Check out the release tag first." >&2
    exit 1
  fi
fi
VER="${TAG#app-v}"
if ! [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Tag '$TAG' is not app-vX.Y.Z." >&2
  exit 1
fi
PUB=$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' pubspec.yaml)
if [ "$PUB" != "$VER" ]; then
  echo "Tag version $VER does not match pubspec.yaml version $PUB." >&2
  exit 1
fi
if ! $DRY && [ -n "$(git status --porcelain)" ]; then
  echo "The tree has uncommitted changes; a release builds the tag as it is." >&2
  exit 1
fi
for f in ios/Flutter/VouchLocal.xcconfig ios/Runner/GoogleService-Info.plist; do
  [ -f "$f" ] || { echo "Missing $f (see docs/building-the-app.md)." >&2; exit 1; }
done

ENV_FILE="$HOME/.appstoreconnect/vouch.env"
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
: "${ASC_KEY_ID:?set ASC_KEY_ID (see the top of this script)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (see the top of this script)}"
KEY="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
[ -f "$KEY" ] || { echo "Missing $KEY." >&2; exit 1; }

IFS=. read -r X Y Z <<<"$VER"
BUILD=$(( X * 10000 + Y * 100 + Z ))
COMMIT=$(git rev-parse --short=7 HEAD)

OPTS=$(mktemp -d)/ExportOptions.plist
cat > "$OPTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$($DRY && echo export || echo upload)</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

echo "Vouch $VER (build $BUILD) at $COMMIT: $($DRY && echo 'dry run, no upload' || echo 'uploading to TestFlight')"
flutter pub get
flutter build xcarchive --release \
  --build-name "$VER" --build-number "$BUILD" \
  --dart-define=VOUCH_COMMIT="$COMMIT"
[ -d build/ios/archive/Runner.xcarchive ] || { echo "No archive was built." >&2; exit 1; }
# flutter also tries to export an IPA through Xcode's account and reports
# "No Accounts" when there is none. That is expected; the export that
# counts is this one, signed with the API key.
echo "Exporting with the App Store Connect API key."
rm -rf build/ios/ipa
xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportOptionsPlist "$OPTS" \
  -exportPath build/ios/ipa \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

if $DRY; then
  IPA=$(ls build/ios/ipa/*.ipa 2>/dev/null || true)
  [ -n "$IPA" ] || { echo "No IPA was written." >&2; exit 1; }
  echo "Signed for the App Store: $IPA"
else
  echo "Uploaded. It appears in App Store Connect > TestFlight after processing (about 10 to 30 minutes)."
fi
