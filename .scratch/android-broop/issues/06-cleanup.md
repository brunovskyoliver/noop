# Broop build cleanup

## Request

Remove unnecessary artifacts and stop processes left by the Android Broop port and release build.

## Completed

- Stopped the idle Gradle 8.7 daemon (PID 5648) and its Kotlin compiler daemon (PID 7704). The Gradle log attributed the last build to this checkout. No build was running.
- Stopped the orphaned emulator network helper (PID 18329), whose working directory and start time matched this task's emulator. It required SIGKILL after SIGTERM did not exit within the grace period.
- Removed the three task-specific Swift build/oracle directories under `.build`, Android intermediates and local Gradle caches, obsolete debug/Demo/test APKs, task-specific temporary locks, emulator helper logs and superseded screenshots.
- Preserved the release APK and metadata at `android/app/build/outputs/apk/full/release/`. Kept all source, tests, lockfiles, ticket reports and final verification evidence. A unique R-R comparison report found in the build folder was moved to the existing evidence directory before cleanup.
- Removed 36 paths representing 2,730,381,312 allocated bytes. Filesystem available space increased by 2,297,266,176 bytes, approximately 2.3 GB, at the final measurement. APFS sharing and concurrent filesystem activity can make these figures differ.

## Verification and retained files

- All 147 modified or untracked source/test files outside the ticket reports matched their pre-cleanup combined checksum.
- The retained release APK still matches SHA-256 `fd2baf69d7c430d7977d78566625b8096827967bc41ba0779691d39a608350bd`.
- The temporary emulator and AVD had already been deleted. All three remaining task-owned build/emulator processes are now stopped.
- The pre-existing shared ADB server and installed toolchains were retained.
- Detailed deletion and measurement records: `/Users/oliver/agent-runs/2026-10-19-android-broop/cleanup-manifest.json`. Final logs, screenshots and the preserved `rr-rundown.md` remain in that directory.

## Remaining

No task-owned running process or temporary build output remains. The release APK, its metadata and final verification evidence are intentionally retained. Earlier debug APK links refer to outputs removed by this cleanup.
