#!/usr/bin/env bash
# Build the iPhone app at a release tag and upload it to TestFlight.
#
#   app/tool/testflight.sh                 # HEAD must be exactly at an app-vX.Y.Z tag
#   app/tool/testflight.sh --dry-run       # build and sign for the App Store, no upload
#   app/tool/testflight.sh --ci [--dry-run]
#
# On a Mac: signing and the upload use an App Store Connect API key kept on
# this Mac, never in the repo or CI: ASC_KEY_ID and ASC_ISSUER_ID in the
# environment or in ~/.appstoreconnect/vouch.env, and the key itself at
# ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8. Xcode manages the
# signing. The identity comes from ios/Flutter/VouchLocal.xcconfig.
#
# --ci: signs by hand with a certificate and profile that are already
# installed (the release job installs them), and the key only uploads.
# Everything comes from the environment: VOUCH_DEVELOPMENT_TEAM,
# IOS_PROFILE_NAME, ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the key
# file). It writes ios/Flutter/VouchLocal.xcconfig, so it refuses to run
# where one exists.
#
# A Mac build carries the Firebase config in ios/Runner/GoogleService-Info.plist,
# for the owner's own push. A --ci build is a published build and must carry
# none: it refuses to run where that file exists, and fails if the archive
# holds one. The build number is X*10000 + Y*100 + Z, as on Android, so each
# version uploads once. See README.md "iPhone releases (TestFlight)".
set -euo pipefail

cd "$(dirname "$0")/.."
DRY=false
CI_MODE=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=true ;;
    --ci) CI_MODE=true ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

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

LOCAL=ios/Flutter/VouchLocal.xcconfig
FIREBASE=ios/Runner/GoogleService-Info.plist
if $CI_MODE; then
  : "${VOUCH_DEVELOPMENT_TEAM:?set VOUCH_DEVELOPMENT_TEAM (the Apple team id)}"
  : "${IOS_PROFILE_NAME:?set IOS_PROFILE_NAME (the name of the App Store provisioning profile)}"
  : "${ASC_KEY_ID:?set ASC_KEY_ID}"
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
  : "${ASC_KEY_PATH:?set ASC_KEY_PATH (the .p8 key file)}"
  KEY="$ASC_KEY_PATH"
  [ -f "$KEY" ] || { echo "No key file at ASC_KEY_PATH." >&2; exit 1; }
  if [ -e "$LOCAL" ]; then
    echo "$LOCAL exists; --ci writes its own and will not replace yours." >&2
    exit 1
  fi
  [ ! -e "$FIREBASE" ] || { echo "$FIREBASE exists; a published build carries no Firebase config." >&2; exit 1; }
  [[ "$VOUCH_DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo "VOUCH_DEVELOPMENT_TEAM is not a 10-character team id." >&2; exit 1; }
  # An Apple Distribution identity of this team, with its private key, in a keychain codesign searches.
  IDENTITY=$(security find-identity -v -p codesigning \
    | awk -v team="($VOUCH_DEVELOPMENT_TEAM)\"" '/"Apple Distribution: / && index($0, team) { print $2; exit }')
  [ -n "$IDENTITY" ] || { echo "No Apple Distribution certificate with its key for team $VOUCH_DEVELOPMENT_TEAM is installed." >&2; exit 1; }
  PROFILE=""
  for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
    for f in "$dir"/*.mobileprovision; do
      [ -f "$f" ] || continue
      name=$(security cms -D -i "$f" 2>/dev/null | plutil -extract Name raw -o - - 2>/dev/null || true)
      if [ "$name" = "$IOS_PROFILE_NAME" ]; then PROFILE=$f; break 2; fi
    done
  done
  [ -n "$PROFILE" ] || { echo "No installed provisioning profile is named '$IOS_PROFILE_NAME'." >&2; exit 1; }
  echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
  echo "Flutter: $(flutter --version 2>/dev/null | head -1)"
  echo "Signing identity: Apple Distribution, SHA-1 $IDENTITY; profile '$IOS_PROFILE_NAME'"
  cat > "$LOCAL" <<EOF
// Written by tool/testflight.sh --ci for this build only.
VOUCH_DEVELOPMENT_TEAM = $VOUCH_DEVELOPMENT_TEAM
VOUCH_CODE_SIGN_STYLE = Manual
VOUCH_CODE_SIGN_IDENTITY = Apple Distribution
VOUCH_PROFILE_SPECIFIER = $IOS_PROFILE_NAME
EOF
  trap 'rm -f "$LOCAL"' EXIT
else
  [ -f "$LOCAL" ] || { echo "Missing $LOCAL (see docs/building-the-app.md)." >&2; exit 1; }
  ENV_FILE="$HOME/.appstoreconnect/vouch.env"
  # shellcheck disable=SC1090
  [ -f "$ENV_FILE" ] && . "$ENV_FILE"
  : "${ASC_KEY_ID:?set ASC_KEY_ID (see the top of this script)}"
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (see the top of this script)}"
  KEY="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
  [ -f "$KEY" ] || { echo "Missing $KEY." >&2; exit 1; }
  [ -f "$FIREBASE" ] || { echo "Missing $FIREBASE (see docs/building-the-app.md)." >&2; exit 1; }
fi

IFS=. read -r X Y Z <<<"$VER"
BUILD=$(( X * 10000 + Y * 100 + Z ))
COMMIT=$(git rev-parse --short=7 HEAD)

echo "Vouch $VER (build $BUILD) at $COMMIT: $($DRY && echo 'dry run, no upload' || echo 'uploading to TestFlight')"
flutter pub get
flutter build xcarchive --release \
  --build-name "$VER" --build-number "$BUILD" \
  --dart-define=VOUCH_COMMIT="$COMMIT"
ARCHIVE=build/ios/archive/Runner.xcarchive
[ -d "$ARCHIVE" ] || { echo "No archive was built." >&2; exit 1; }
if $CI_MODE; then
  # What is signed and uploaded is this app. Nothing named like a Firebase config may be in it.
  FOUND=$(find "$ARCHIVE/Products/Applications" -iname 'GoogleService-Info*.plist' -print -quit)
  [ -z "$FOUND" ] || { echo "The archive carries a Firebase config ($FOUND); not exporting it." >&2; exit 1; }
fi

OPTS=$(mktemp -d)/ExportOptions.plist
if $CI_MODE; then
  BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "$ARCHIVE/Info.plist")
  SIGNING="<key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>teamID</key><string>$VOUCH_DEVELOPMENT_TEAM</string>
  <key>provisioningProfiles</key><dict><key>$BUNDLE</key><string>$IOS_PROFILE_NAME</string></dict>"
else
  SIGNING="<key>signingStyle</key><string>automatic</string>"
fi
cat > "$OPTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$($DRY && echo export || echo upload)</string>
  $SIGNING
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

# flutter build xcarchive does not export. This export signs the archive and,
# unless it is a dry run, uploads it with the API key. Only a Mac run may let
# Xcode create a certificate or profile; in CI the key can only upload.
EXPORT=(xcodebuild -exportArchive
  -archivePath "$ARCHIVE"
  -exportOptionsPlist "$OPTS"
  -exportPath build/ios/ipa
  -authenticationKeyPath "$KEY"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID")
$CI_MODE || EXPORT+=(-allowProvisioningUpdates)
echo "Exporting with the App Store Connect API key."
rm -rf build/ios/ipa
LOG=$(mktemp)
if ! "${EXPORT[@]}" 2>&1 | tee "$LOG"; then
  if grep -qiE 'Redundant Binary Upload|bundle version must be higher|already been uploaded' "$LOG"; then
    echo "Build $BUILD of Vouch $VER was already uploaded to App Store Connect. Release a new version to upload again." >&2
  fi
  exit 1
fi

if $DRY; then
  IPA=$(ls build/ios/ipa/*.ipa 2>/dev/null || true)
  [ -n "$IPA" ] || { echo "No IPA was written." >&2; exit 1; }
  echo "Signed for the App Store: $IPA"
else
  echo "Uploaded. It appears in App Store Connect > TestFlight after processing (about 10 to 30 minutes)."
fi
