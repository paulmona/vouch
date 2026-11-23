# Vouch app

The Vouch mobile app, in Flutter, for Android and iOS. It is built against
the contract in `../api/openapi.yaml`.

To build and install your own copy (your app id, Apple team and Firebase
project), follow [docs/building-the-app.md](../docs/building-the-app.md).
This file is for working on the app itself.

## Build and test

Requirements: Flutter stable (3.44+), JDK 17, and the Android SDK
`flutter doctor` asks for. iPhone builds also need Xcode 26+ and CocoaPods
(`brew install cocoapods`).

```sh
cd app
flutter pub get
flutter analyze && flutter test
flutter run                      # connected phone, emulator or simulator
```

The identity settings live in `ios/Flutter/Vouch.xcconfig` (override them in
the gitignored `VouchLocal.xcconfig`, which must set your Apple team id) and
the gitignored `android/vouch.properties`. The Firebase files
(`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`)
are gitignored too. Android builds and runs without its file, with no push;
the iOS build needs its file.

The published APK (`release-app.yml`, on `app-v*` tags) is built with no
Firebase config, so it gets no push notifications: its owner opens Vouch to
see requests. There is no shared push relay, and an app that carried the
publisher's config would register every phone that installs it with the
publisher's Firebase project. The release job refuses to build where the
file exists and checks the finished APK for one. For push, build the app
yourself with your own Firebase project
([docs/building-the-app.md](../docs/building-the-app.md)). CI on pull
requests does not build an APK; it runs format, analyze and tests.

### Notes

- A **debug** iPhone build only starts from `flutter run` or Xcode; opened
  from the home screen it closes at once. Install a release build to keep.
- With Xcode 27, `flutter build ios --simulator` fails in Flutter's
  framework thinning step. `flutter run -d <simulator>` works.
- `flutter test integration_test/... -d <iPhone>` installs its own build
  under the same bundle id and removes it afterwards, taking the app with
  it. Reinstall after.
- To hand an iPhone a pairing link without typing it:

  ```sh
  xcrun devicectl device process launch --terminate-existing \
    --device <UDID> --payload-url 'vouch://pair?v=1&server=...&token=...' \
    <bundle id>
  ```

## Layout

| Path | What |
| --- | --- |
| `lib/main.dart` | Entry: edge-to-edge, font licences, `ProviderScope` |
| `lib/app.dart` | `MaterialApp.router`, routes (`go_router`) |
| `lib/api/` | Request signing (`Canonical`, `DeviceSigner`, `SigningClient`), `VouchApi`, Cloudflare Access |
| `lib/keys/` | `DeviceKeyStore` (Dart side of the key channel) and `KeystoreSigner` |
| `lib/pairing/` | `PairLink` (QR payload), `PairingService`, `PairedDevice` |
| `lib/requests/` | Fetching requests, deciding, the shown digest |
| `lib/push/` | Firebase Messaging, the push handler and notifications |
| `lib/sms/` | The optional SMS module: conversations and permitted contacts |
| `lib/platform/` | `AppSettings` (device name, battery optimisation) and biometric wording |
| `lib/theme/` | Brand tokens and the Material 3 theme (light and dark) |
| `lib/screens/` | Home, Pair, Request, Settings, Messages, About |
| `assets/fonts/` | Inter and Instrument Serif, bundled (OFL) |
| `packages/vouch_api/` | **Generated** Dart client from `../api/openapi.yaml`. Never edit by hand |
| `tool/generate_api.sh` | Regenerates `packages/vouch_api` (pinned openapi-generator) |
| `android/` | Android project and `DeviceKeyChannel.kt` |
| `ios/` | Xcode project and the Swift channels (see [iOS](#ios)) |

State management is Riverpod (`flutter_riverpod`, no code generation).

## API client and signing

The contract is `../api/openapi.yaml`. The Dart client in
`packages/vouch_api` is generated from it:

```sh
./tool/generate_api.sh      # needs Java 17 and npx
```

CI regenerates and fails if the committed client differs, so the app can't
drift from the spec silently. After a contract change: regenerate, fix
whatever no longer compiles, commit both.

Every call is signed (`lib/api/`). `SigningClient` wraps the HTTP client the
generated code uses: it hashes the exact body bytes, builds the canonical
string (`METHOD\nTARGET\nBODY_SHA256\nTIMESTAMP\nNONCE`), signs it with the
`DeviceSigner`, and adds the `X-Vouch-*` headers. `SoftwareSigner` is a
pure-Dart P-256 key for tests. `test/api/` checks all of this against
`../api/test-vectors.json`.

A decision also carries `shown_digest`, a hash of the request exactly as the
screen showed it (`lib/requests/shown_digest.dart`), so an answer only
counts for the request the owner saw.

## Device keys

Each phone holds two P-256 keys that never leave its secure hardware: a
**transport key** that signs ordinary calls without a prompt, and a
**decision key** that signs approvals and needs a fingerprint or Face ID for
every single use. Cancelling the prompt yields no signature, so nothing is
sent.

**Android:** `DeviceKeyChannel.kt` keeps the keys in the Android Keystore
(StrongBox where the phone has it, else the TEE) and exposes them over the
`ai.viewbridge.vouch/device_key` method channel. The decision key signs only
inside a `BiometricPrompt` `CryptoObject`. Keys carry an attestation chain
with SHA-256 of the setup token as the challenge. `MainActivity` is a
`FlutterFragmentActivity` because the prompt needs one.

**iOS:** `DeviceKeyChannel.swift` makes the keys in the Secure Enclave. The
decision key uses `.biometryCurrentSet` (Face ID or Touch ID per signature;
an enrolment change destroys it). iOS has no key attestation, so the server
records an iPhone as `client_asserted`.

Debug builds have Settings > Developer > Key self-test to exercise the keys
on a device. On the Android emulator, enrol a fingerprint first (set a PIN,
then Settings > Security > Fingerprint, and `adb -e emu finger touch 1` at
the sensor step; the same command answers the prompt).

## Pairing

`vouch://pair?v=1&server=<URL>&token=<setup token>`, from the QR code or
pasted. `PairingService` makes both keys, signs `vouch-pair-v1\n<token>`
with the decision key under one "Confirm pairing" prompt, and posts the pair
request signed by the transport key. The pairing (device id, server, policy)
is kept in SharedPreferences. Settings > Forget this server undoes it on the
phone.

Plain `http` servers are accepted only on this phone or the local network,
with a warning; anything else needs HTTPS.

## iOS

One Dart codebase. `ios/` holds the Xcode project and the Swift twins of the
Android channels (same channel names and error codes, so `lib/` has almost
no platform branches):

| File | What |
| --- | --- |
| `ios/Runner/DeviceKeyChannel.swift` | Secure Enclave keys (see [Device keys](#device-keys)) |
| `ios/Runner/PairLinkChannel.swift` + `SceneDelegate.swift` | `vouch://pair` links, and the Local Network prompt before pairing with a LAN server |
| `ios/Runner/AppSettingsChannel.swift` | Device name, `biometryName`, battery calls as no-ops |
| `ios/Runner/ContactPickerChannel.swift` | The system contact picker, for the SMS module |
| `ios/Runner/Runner.entitlements` | `aps-environment` and time-sensitive notifications |

Requests arrive as time-sensitive notifications with no buttons
(`lib/push/notifications.dart`): the tap opens the request, and the decision
is made there. iOS
doesn't wake a force-quit app for a background push, so the server also
sends a visible alert, and Home checks for pending requests while it is on
screen. Minimum iOS 17.

`integration_test/device_key_test.dart` exercises the real key channel on a
device or simulator. On the simulator enrol Face ID first (Features > Face
ID > Enrolled) and answer the prompt with
`xcrun simctl spawn booted notifyutil -p com.apple.BiometricKit_Sim.pearl.match`.

## Against a local server

The Android emulator reaches the Mac as `10.0.2.2`. An emulator's key
attestation chains to a software root, which the server rightly refuses, so
run the server with the policy off and turn off *Send key attestation* on
the pair screen (debug builds only):

```sh
mkdir -p /tmp/vouch-dev && cat > /tmp/vouch-dev/config.toml <<'EOF'
[server]
name = "dev"
[policy]
require_user_auth = false
[app]
host = "127.0.0.1"
port = 8770
public_url = "http://10.0.2.2:8770"
[sockets]
broker = "/tmp/vouch-dev/broker.sock"
broker_group = ""
admin = "/tmp/vouch-dev/admin.sock"
[store]
path = "/tmp/vouch-dev/approver.db"
EOF
(cd ../server && npm ci && node src/main.ts --config /tmp/vouch-dev/config.toml &)
(cd ../server && node src/cli.ts --socket /tmp/vouch-dev/admin.sock setup-code)
```

Socket paths must stay under 107 bytes, hence `/tmp`. A real phone needs the
real policy and attestation: point `public_url` at the computer's LAN
address. A mock of the contract also works for UI work:
`npx @stoplight/prism-cli mock ../api/openapi.yaml`.

## Security tests

"No signature without a fingerprint" is enforced by the Android Keystore, so
it is tested there: an instrumented test
(`android/app/src/androidTest/.../DeviceKeySecurityTest.kt`) shows that the
decision key won't sign without the system prompt, that the transport key
signs and verifies, and that the decision key carries an attestation
extension. It needs a device or emulator with a fingerprint enrolled:

```sh
cd android && ./gradlew connectedDebugAndroidTest
```

CI has no emulator, so this is a local check. The Dart tests cover the layer
above: a cancelled prompt sends nothing, decisions are signed by the
decision key and not the transport key, and pairing sends nothing when the
proof prompt is cancelled.

## Android releases

Tagging `app-vX.Y.Z` on main runs `.github/workflows/release-app.yml`: a
release APK signed with the upload key, attached to a GitHub Release with
its `.sha256` and the signing certificate's SHA-256 in the notes. The tag
must equal `version:` in `pubspec.yaml`; `versionCode` is
`X*10000 + Y*100 + Z`, so it always rises. The About screen shows the
version, build number and short commit. Release builds are checked to be
signed by the upload key and to carry no cleartext allowance.

One-time setup for a fork: generate an upload keystore and keep it, and its
password, somewhere safe. Nothing below is committed (`.gitignore` excludes
`*.jks`, `*.keystore` and `key.properties`).

```sh
keytool -genkeypair -v -keystore ~/vouch-upload.jks -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 -alias vouch-upload \
  -dname "CN=Vouch upload"
```

A PKCS12 keystore uses the same password for the store and the key. Then set
the secrets on the `release` environment (type the passwords at the prompt).
Set up that environment first, as step 1 of
[docs/maintaining.md](../docs/maintaining.md) says, and store these as
environment secrets, not repository secrets: a repository secret can be read
by any workflow.

```sh
gh secret set --env release ANDROID_UPLOAD_KEYSTORE_B64 --body "$(base64 -i ~/vouch-upload.jks)"
gh secret set --env release ANDROID_KEYSTORE_PASSWORD     # prompts
gh secret set --env release ANDROID_KEY_ALIAS --body vouch-upload
gh secret set --env release ANDROID_KEY_PASSWORD          # prompts (same as the store password)
```

To cut a release, bump `version:` in `pubspec.yaml` on main, then tag
`app-vX.Y.Z` and push the tag. A release build without the upload
keystore (`ANDROID_KEYSTORE_*` or `android/key.properties`) stops with an
error; there is no debug-key fallback. Use `flutter run` or a debug build for
local testing.

## iPhone releases (TestFlight)

`tool/testflight.sh` builds the app at an `app-vX.Y.Z` tag, signs it for
the App Store and uploads it to TestFlight. It runs on a Mac and signs with
an App Store Connect API key kept on that Mac, never in the repo or CI. The
build number is `X*10000 + Y*100 + Z`, as on Android, so each version
uploads once.

```sh
git checkout app-vX.Y.Z   # the release tag to build
app/tool/testflight.sh             # or --dry-run: sign, don't upload
```

It uses the same local files as any build: `VouchLocal.xcconfig` (bundle
id and team) and `GoogleService-Info.plist`.

One-time setup, by the account holder:

1. **App record.** In [App Store Connect](https://appstoreconnect.apple.com),
   Apps > + > New App: platform iOS, your bundle id, a name, a SKU (any
   unique string). Accept any agreement App Store Connect shows as pending.
2. **API key.** Users and Access > Integrations > App Store Connect API >
   Team Keys > +, role **Admin** (an App Manager key can't create the
   distribution certificate from the command line). Download the `.p8`
   (once only) to `~/.appstoreconnect/private_keys/`, keeping its
   `AuthKey_<KEY ID>.p8` name, and put the two ids in
   `~/.appstoreconnect/vouch.env`:

   ```sh
   ASC_KEY_ID=<Key ID>
   ASC_ISSUER_ID=<Issuer ID, above the keys table>
   ```

   The first run creates the Apple Distribution certificate and the App
   Store profile. Revoke the key in the same list if the Mac is lost.
3. **Test information.** TestFlight > Test Information: a beta description,
   a feedback email, and a contact for Beta App Review.

Builds are available to internal testers (people on the team in App Store
Connect) once processed. A group of external testers (anyone, by email
or a public link) needs the first build of each version to pass Beta App
Review. The reviewer can't pair without a server, so give them a way in
under Test Information > Review Notes, for example a pairing code for a
demo server that stays open during review.

## Design system

Brand tokens are in `lib/theme/brand.dart`. The theme is
`ColorScheme.fromSeed(#c2410c)` pinned to the brand palette, so the primary
is exactly `#c2410c` in light and `#ea580c` in dark. `test/theme_test.dart`
checks WCAG AA contrast for every pairing the UI relies on. Dynamic colour
is deliberately off: a security prompt shouldn't be recoloured by the
wallpaper.

Type is Inter throughout, with heavier headings and labels. Instrument Serif
is used once, for the tagline on the About screen.

Buttons on security actions follow one scheme: **Approve once** is a
`FilledButton` (accent), **Always allow** is `FilledButton.tonal`, **Deny**
is an `OutlinedButton`. All are 56dp tall for thumb reach.
