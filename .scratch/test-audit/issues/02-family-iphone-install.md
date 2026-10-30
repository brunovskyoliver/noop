# Family iPhone installation

Requested on 2026-10-19. Install Broop on the connected family member's iPhone
using the paid Apple developer team already configured on this Mac.

## Device and preparation

- Target: iPhone Air, named `iPhone užívateľa Frantisek`, running iOS 26.6.2.
- Device identifier: `00008150-001569941187801C`.
- USB connection and pairing were confirmed. Broop was absent before installation.
- Developer Mode was initially disabled. The first device-targeted build timed out
  waiting for that preparation. The user enabled it and restarted the phone;
  CoreDevice subsequently confirmed Developer Mode enabled and the device ready.
- The Xcode project was regenerated from `project.yml`. Release output is isolated
  in the gitignored `build/family-iphone-deploy/` directory. Temporary deployment
  logs are in this session's `/tmp/agents/` directory.

## Result

Installed and launched Broop 12.1.0 (436), bundle identifier
`com.oliverbrunovsky.noop`, over USB. The existing paid developer team was used;
the family member's Apple Account was not needed. Xcode automatically registered
the destination device and refreshed the development provisioning profiles.
Both the main app and widget profiles include this device and expire on
2027-10-19. The existing automatic refresh job was not reconfigured; it continues
to target Oliver's original iPhone.

## Verification

- Generic iOS Release build: `BUILD SUCCEEDED`.
- Subsequent device-targeted Release build with automatic provisioning and device
  registration: `BUILD SUCCEEDED`.
- `codesign --verify --deep --strict --verbose=2` passed for the complete app.
- Both relevant iPhone provisioning profiles were decoded locally and checked for
  the destination identifier before installation.
- CoreDevice installation and launch both returned success. The post-install app
  query confirmed Broop 12.1.0 (436).
- A subsequent process query found PID 682 running from the newly installed
  `D65DDDCA-4E5D-43DE-941E-3F2CD4981D64/NOOP.app` bundle.
- The tracked working-tree diff is byte-identical to the pre-deployment snapshot
  (SHA-256 `0bfb861dd720f8357cb24f9ee9fd13f037fab21ce490f5ee888ec6ff0231088b`).
  `git diff --check` passes. No application source, dependency lockfile or signing
  configuration was changed.

No installation blockers remain. Verification covers signing, installation and
launch. Onboarding, strap pairing, Health permissions and WHOOP export import
remain user setup; those flows were not exercised during this installation.

## Cleanup

Removed the isolated build output, prepared app, temporary deployment logs and
generated Swift scratch files after verification: 15,977 files occupying
2,574,565,376 allocated bytes. Both disposable directories are confirmed absent.
The empty `build/` parent was also removed. The generated Xcode project, its tracked
dependency lockfile, signing profiles and this report are retained.
