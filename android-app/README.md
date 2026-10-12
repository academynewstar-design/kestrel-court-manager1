# Kestrel Sports Club Android test app

This is a lightweight Android launcher for https://kestrelsports.ca using Android Custom Tabs. It shares the user's browser login session and preserves Google sign-in. It is **not** a fully native or offline application. An address bar may appear; fullscreen Trusted Web Activity requires verified Digital Asset Links and release signing.

## Get the test APK

Open GitHub → Actions → **Build Android test APK** → latest successful run → Artifacts → **Kestrel-Sports-Club-Android-Test-APK**. Download the zip, extract `app-debug.apk`, and install on Android (allow installation from this source if prompted). This is a debug-signed testing build, not a Play Store release.

The GitHub workflow also runs automatically whenever files under `android-app/` change. It does not modify the existing website or database.
