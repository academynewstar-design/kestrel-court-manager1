# Kestrel Sports Club Android app

This is a lightweight Android Custom Tabs launcher for https://kestrelsports.ca. It uses the live website and shares the browser's Google login session. It is not an offline or fully native app.

## Testing
The **Build Android test APK** GitHub Actions workflow builds an installable debug APK automatically.

## Signed release APK for WhatsApp distribution
Never distribute the debug APK as the production release. A **permanent release keystore** is required. Store it securely outside the public repository and keep a backup: losing it prevents installing future updates over the existing app.

Create a signing key using Java keytool (on your own secure computer):
```bash
keytool -genkeypair -v -keystore kestrel-release.jks -alias kestrel -keyalg RSA -keysize 3072 -validity 10000
```
In GitHub repository Settings → Secrets and variables → Actions, add four **repository secrets**:
- `KESTREL_KEYSTORE_BASE64`: base64 encoding of the entire JKS file (single line)
- `KESTREL_KEYSTORE_PASSWORD`: keystore password
- `KESTREL_KEY_ALIAS`: alias used above (e.g. `kestrel`)
- `KESTREL_KEY_PASSWORD`: key password

Then GitHub → Actions → **Build Android test APK** → **Run workflow**. The `release` job produces `Kestrel-Sports-Club-Android-Release-APK`. Download its ZIP artifact and extract `app-release.apk`.

Keep the same applicationId and signing key for all future updates; increment `versionCode` before each new release.

Android users installing from WhatsApp or a browser may need to approve 'Install unknown apps'. The website can update independently without reinstalling this APK. Do not commit the keystore, passwords, or base64 key to the public repository.
