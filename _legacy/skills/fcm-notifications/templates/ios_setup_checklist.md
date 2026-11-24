# iOS FCM setup checklist

Greenfield-ready. Each item maps to a Rule in SKILL.md or an item in the host project's `pubspec.yaml`.

## Versions

- **Flutter SDK** ≥ 3.38.0 — required for iOS 26 + Xcode 26 support.
- **iOS deployment target** ≥ 13.0 — required by `firebase_messaging` 15+.
- **Xcode** ≥ 26.0 — required for iOS 26 SDK.
- **`firebase_messaging`** ≥ 16.1.1 — 16.1.0 briefly re-introduced an iOS 18 duplicate-notification regression; 16.1.1 re-fixed it.

## iOS dependency manager

**Default: Swift Package Manager (SPM).** Firebase iOS SDK CocoaPods support ends **October 2026** ([Firebase migration guide](https://firebase.google.com/docs/ios/cocoapods-deprecation)). After that date, no new Firebase versions will be published to CocoaPods.

- Greenfield projects: SPM. Flutter's stable SPM support landed in 3.34 and improved through 3.41.
- Existing CocoaPods projects: continue to work until October 2026, but plan migration. Mixing SPM and CocoaPods in the same target is supported but creates dependency-resolution complexity — consolidate when feasible.

## iOS lifecycle (AppDelegate vs SceneDelegate)

**Default: `UIApplicationDelegate`.** This is the path the FlutterFire docs assume; the skill's templates are written against it. No additional setup beyond the standard Flutter Xcode template.

`UISceneDelegate` support is opt-in:
- Added in `firebase_messaging` 16.1.0 (PRs [#17888](https://github.com/firebase/flutterfire/pull/17888) / [#17905](https://github.com/firebase/flutterfire/pull/17905)).
- Known issues as of writing: [FlutterFire #18110](https://github.com/firebase/flutterfire/issues/18110) (crash on foreground notification with UIScene), [flutter/flutter #185048](https://github.com/flutter/flutter/issues/185048) (`onMessage` stream never fires; `Messaging.messaging().delegate` is nil after plugin registration).

Adopt SceneDelegate only if the project has a concrete UIScene need (multi-window, iPadOS multi-instance).

## Xcode capabilities

Open `ios/Runner.xcworkspace` (or `.xcodeproj` if SPM-only) → target `Runner` → Signing & Capabilities → **+ Capability**:

1. **Push Notifications**
2. **Background Modes** → check **Remote notifications**

## Entitlements file

`ios/Runner/Runner.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>aps-environment</key>
  <string>development</string>
</dict>
</plist>
```

**Critical APNs sandbox matrix** — Xcode auto-flips this for some build configs, but verify:

| Build config | `aps-environment` |
|---|---|
| Xcode Run (debug) | `development` |
| Ad Hoc | `production` |
| TestFlight | `production` |
| App Store | `production` |

Wrong sandbox = no push delivery. A TestFlight build with `development` silently receives nothing.

## Info.plist

```xml
<key>UIBackgroundModes</key>
<array>
  <string>remote-notification</string>
</array>
```

Only enable this if the background handler does meaningful work — otherwise iOS may throttle wake-ups. The skill's default handler is a Firebase-init shim; remove this entry if the project never uses silent push.

## APNs key in Firebase Console

1. Apple Developer Portal → Certificates, Identifiers & Profiles → Keys → **+** → enable **Apple Push Notifications service (APNs)** → download the `.p8` file.
2. Note the **Key ID** and your **Team ID**.
3. Firebase Console → Project Settings → Cloud Messaging → Apple app configuration → **Upload `.p8`** with Key ID + Team ID.

The `.p8` key is single-use — store it in a secure location (1Password / vault). It cannot be re-downloaded.

## AppDelegate.swift

Default Flutter template needs no edits unless you opt into Rule 6's tap-after-crash mitigation (native payload persistence via `userNotificationCenter(_:didReceive:)` + App Group `UserDefaults`).

## Verifying

- `flutter run` on a physical iOS device (NOT simulator — APNs is unavailable there).
- After login, verify the cubit's `TokenRegistrationStatus` reaches `registered`.
- Send a test push via the FCM HTTP v1 API (Console "Test send" uses a different shape — see reference §11).
