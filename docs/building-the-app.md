# Building your own Vouch app

Vouch has no shared push relay. Every installation pushes to its phones
through its own Firebase project, so you build the app yourself: with your
own app id, signed with your own Apple or Android keys, and holding your
Firebase project's config. This guide goes from an empty Firebase project to
the app on your phone.

You need a Mac with Xcode for iPhone builds, and Flutter (stable, 3.44 or
later) for both platforms. `flutter doctor` lists anything missing.

## 1. Choose your app identity

The tree builds the upstream app (`ai.viewbridge.vouch`) unless you say
otherwise. Pick your own ids: a reverse domain you control, for example
`com.example.vouch`. Then create two files. Both are gitignored, so they
stay out of commits and survive pulls.

**iOS:** `app/ios/Flutter/VouchLocal.xcconfig`

```
VOUCH_BUNDLE_ID = com.example.vouch
VOUCH_DEVELOPMENT_TEAM = ABCDE12345
VOUCH_DISPLAY_NAME = Vouch
```

Your team id is under Membership details at
[developer.apple.com/account](https://developer.apple.com/account).

**Android:** `app/android/vouch.properties`

```
applicationId=com.example.vouch
appName=Vouch
```

`VOUCH_DEVELOPMENT_TEAM` has no default: set it, or the iPhone build can't
sign. Anything else you leave out keeps the upstream value. The defaults are in
`app/ios/Flutter/Vouch.xcconfig` and `app/android/app/build.gradle.kts`.

## 2. Create the Firebase project

1. In the [Firebase console](https://console.firebase.google.com), create a
   project. Analytics isn't needed.
2. **iPhone:** add an iOS app with your bundle id. Download
   `GoogleService-Info.plist` and put it at
   `app/ios/Runner/GoogleService-Info.plist`.
3. **Android:** add an Android app with your applicationId. Download
   `google-services.json` and put it at
   `app/android/app/google-services.json`.

Both files are gitignored. The Android build runs without its file, but the
app gets no pushes. The iPhone build needs its file.

## 3. Let Firebase push to iPhones (APNs)

Firebase reaches iPhones through Apple's push service, with a key from your
Apple developer account. Pushes need a paid Apple Developer Program
membership; a free personal team can't use them.

1. At [developer.apple.com](https://developer.apple.com/account/resources/authkeys/list),
   open **Keys**, create a key with **Apple Push Notifications service
   (APNs)** enabled, and download the `.p8` file. Note the Key ID. You can
   download it only once.
2. In the Firebase console, open **Project settings > Cloud Messaging >
   Apple app configuration**. Upload the `.p8` as an **APNs authentication
   key**, with its Key ID and your team id.

The upload is per iOS app. If your project holds more than one (say, a
second build with another bundle id), upload the key to each of them. An
app without one gets no pushes, and the server logs
`THIRD_PARTY_AUTH_ERROR`. The app still finds new requests while it's open,
so a missing key is easy to miss.

## 4. Give your server the project's credentials

The server sends pushes with a Firebase service account from the same
project: **Project settings > Service accounts > Generate new private
key**. Treat the downloaded JSON as a secret. The server's configuration
guide says where it goes.

## 5. Build and install

### iPhone

Sign in to Xcode with your Apple ID (**Xcode > Settings > Accounts**). The
first build then creates a signing certificate and a provisioning profile
for your bundle id. macOS asks for the login keychain password; choose
Always Allow.

```sh
cd app
flutter pub get
flutter build ios --release
xcrun devicectl list devices                     # your iPhone's id
xcrun devicectl device install app --device <id> build/ios/iphoneos/Runner.app
```

Use a release build for the phone. A debug build starts only from Xcode or
`flutter run`; opened from the home screen, it closes at once.

### Android

```sh
cd app
flutter pub get
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Or copy the APK to the phone and open it, allowing installs from that
source. Without a signing key, the release APK is signed with the debug
key. That's fine for your own phone. To sign with your own key, see
**Releases** in `app/README.md`.

## 6. Pair

On the server, create a setup code. In the app, scan its QR code, or paste
the `vouch://pair?...` link. If your server is behind Cloudflare Access,
enter the service token first: see [Cloudflare Access](cloudflare-access.md).

## Notes

- **Two Vouch apps on one phone.** Different ids install side by side, but
  both handle `vouch://` links, so a tapped pairing link may open either one.
  Paste the link into the app you mean instead.
- **Branding.** The app carries the Viewbridge mark and colours. They live
  in `app/lib/theme/brand.dart`, `app/lib/widgets/vouch_mark.dart` and the
  launcher icons. A build for your own phones can keep them. A build you
  distribute must use your own name, mark and application id (see `NOTICE`):
  change those files, and set your own name and ids in step 1.
