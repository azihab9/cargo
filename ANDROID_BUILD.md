# CargoFlow Android APK

CargoFlow is packaged for Android with Capacitor. The Android app bundles the current `index.html` from the repository, so changes to the web app are included in the next APK build.

## Build an APK with GitHub Actions

1. Open the repository on GitHub.
2. Select **Actions**.
3. Open **Build CargoFlow APK**.
4. Wait for the workflow to finish successfully.
5. Open the completed run and download the **CargoFlow-Android-debug-APK** artifact.
6. Extract the ZIP and install `app-debug.apk` on the Android device.

The workflow also runs automatically when `index.html` or the Android build configuration changes on the `main` branch.

## Build locally on Windows

Requirements: Node.js 22 or newer, Android Studio, and an Android SDK.

```bash
npm install
npm run cap:add:android
npm run cap:sync:android
npx cap open android
```

In Android Studio, build the app using **Build > Build Bundle(s) / APK(s) > Build APK(s)**.

After changing `index.html`, run `npm run cap:sync:android` again before building.

## Notes

- The current workflow produces a **debug APK** for internal testing and installation. A separately signed release APK is needed for production distribution or Play Store publishing.
- CargoFlow still uses Supabase and external JavaScript libraries, so an internet connection is required for login, cloud data, and those libraries.
- The web app at the repository root remains the source of truth; the `www/` folder is generated during the build.
