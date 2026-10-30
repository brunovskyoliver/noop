# Android Broop release APK

## Request

Produce an installable release APK instead of the earlier debug APK.

## Result

- Built `android/app/build/outputs/apk/full/release/app-full-release.apk`, 23,617,815 bytes.
- Variant: `fullRelease`. Version: `12.1.0-staging` (555). Application ID: `com.noop.whoop.staging`.
- Used the repository's release workflow command, `:app:assembleFullRelease -PstagingRelease`, with JDK 17. The existing fork key signs this variant. The private official release configuration, `android/keystore.properties`, is absent, so the repository requires the staging suffix for this local build. It can install beside the official and debug applications.
- No production source or build configuration was changed for this request.

## Verification

- Gradle build and release vital lint passed: `BUILD SUCCESSFUL in 2m 33s`.
- `apksigner verify --verbose --print-certs` verified the APK's v2 signature.
- APK manifest/badging and generated release `BuildConfig` confirm debugging is disabled.
- Package and version metadata match the staging release configuration.
- SHA-256: `fd2baf69d7c430d7977d78566625b8096827967bc41ba0779691d39a608350bd`.
- Build log, signature output, badging and JSON metadata are saved in `/Users/oliver/agent-runs/2026-10-19-android-broop/` as `android-release-build.log`, `release-apk-signature.txt`, `release-apk-badging.txt` and `release-apk-manifest.json`.

## Remaining

The release APK was not run on a device in this follow-up. Earlier emulator and source parity verification, the unchanged unit-test failure and real-strap validation limits are recorded in [01-port.md](01-port.md).
