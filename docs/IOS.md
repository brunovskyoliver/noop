# iOS — Install & Build

> **iOS is now a direct download (v1.96).** Grab **`NOOP-v<version>-ios.ipa`** from the
> [Releases](https://github.com/ryanbr/noop/releases) page and install it with **AltStore** or **SideStore** — see
> **[Install (sideload)](#install-sideload)** below. No Mac, no Xcode, no App Store, and no Apple
> Developer account needed — **and NOOP stays anonymous**, because the `.ipa` has no Apple developer
> signature and **you** sign it on your own iPhone with your own free Apple ID. It carries only a
> replaceable ad-hoc capability template so the sideloader can provision HealthKit and the App Group
> shared with the widget. The app target (`NOOPiOS` +
> `NOOPiOSWidgets`) also still builds from source in Xcode if you'd rather (**[Build from source](#build-from-source)**).
> A CI job ([`app-build.yml`](../.github/workflows/app-build.yml)) compiles the iOS
> target on every relevant change so iOS can't silently break.

## Install (sideload)

The `.ipa` is **not signed by an Apple developer identity** — that's what keeps the project
anonymous. Its replaceable ad-hoc signature only describes the capabilities AltStore/SideStore must
provision; iOS won't run it until the sideloader signs it **on your device, with your own free Apple
ID**. Nothing about this touches NOOP's identity or Apple's servers on our side.

1. **Install a sideloader on your computer** — [AltStore](https://altstore.io) or
   [SideStore](https://sidestore.io) (both free). Follow their one-time setup (it installs a helper +
   AltStore/SideStore onto your iPhone using your own Apple ID).
2. **Download `NOOP-v<version>-ios.ipa`** from [Releases](https://github.com/ryanbr/noop/releases) to your iPhone (or your
   computer, then AirDrop/transfer it).
3. **Open the `.ipa` with AltStore/SideStore** (Share → AltStore, or the app's "+" button). It signs
   and installs NOOP. First launch may need **Settings → General → VPN & Device Management → trust
   your Apple ID**.

### If AltStore's Error Log says "Install NOOP Failed"

The same failure also shows up **on the phone**, in AltStore's own Error Log, where it names NOOP and so
looks like NOOP's fault:

> **Install NOOP Failed** — `NSCocoaErrorDomain 3840`
> *The data couldn't be read because it isn't in the correct format.*

**Read the whole log before concluding anything.** If it also contains:

> **Refresh AltStore Failed** — `NSCocoaErrorDomain 3840`

then AltStore could not refresh **its own app**, which nothing about NOOP's `.ipa` or NOOP's source can
cause. Every "… Failed" line is the same decode failure hitting whatever AltStore happened to be doing at
that minute — installing NOOP, refreshing NOOP, refreshing itself. The NOOP-named lines are the symptom,
not the cause.

`NSCocoaErrorDomain 3840` is a parse error: AltStore expected structured data and got something else back
(usually an HTML page). See the section below — it is the same underlying problem as the desktop sign-in
failure, just reported from the phone instead of AltServer.

### If AltServer can't sign in with your Apple ID

A failure at **step 1** — before NOOP is involved at all — looks like this:

> **AltServer could not sign in with your Apple ID. The data is not in the correct format.**
>
> `NSCocoaErrorDomain 3840` · *Encountered unknown tag html on line 1*

**This is a known AltStore bug on OS 26.2, not a problem with your setup.** It is reported upstream in
[altstoreio/AltStore#1695](https://github.com/altstoreio/AltStore/issues/1695) and
[#1699](https://github.com/altstoreio/AltStore/issues/1699), on macOS Tahoe 26.2 with iOS/iPadOS 26.2, and
at the time of writing there is no maintainer fix or workaround. Nothing you can change on your machine
resolves it.

What the error means, for the record: AltServer asked Apple's ID service for a property list and received
an **HTML page**, so the parser hit `<html>` on the first line. The "malformed data byte group / invalid
hex" line beneath it is the same failure reported by the older-style parser, not a second fault.

**What actually works today:**

- **Use [SideStore](https://sidestore.io) instead.** It is a separate implementation that does not go
  through AltServer's Apple ID sign-in, and NOOP's source works there identically — the same URL, the same
  auto-updates. This is the practical answer while the upstream bug is open.
- **Install the `.ipa` directly** with any sideloader that signs on-device, if you prefer not to add a
  source at all.
- **Watch the issues above** if you would rather wait for AltStore itself.

Local network filtering — a DNS blocker, a VPN, a captive portal — can produce an identical-looking error
by returning a block page, so it is worth ruling out if you have any. But it is **not** the usual cause,
and the two reports that prompted this note were both the upstream bug.

This is AltStore's own setup rather than anything NOOP controls, but it is the first step of the install,
so it is written down here rather than left as a dead end.

### Add NOOP as a source (recommended — auto-updates)

So you never have to manually re-download, add NOOP's **source** to AltStore/SideStore once — new
releases then show up (and re-sign) automatically:

**Source URL:** `https://raw.githubusercontent.com/ryanbr/noop/main/altstore-source.json`

> Make sure you copy the **raw** URL above exactly. If a sideloader says **"given data not valid
> JSON"** when you add the source, you've pasted a normal web page URL (which returns HTML) instead of
> the raw file — use the `raw.githubusercontent.com` URL above.

- **AltStore:** open AltStore → **Browse** tab → tap **＋** (top-left) → paste the URL → **Add Source**.
  NOOP appears under the source; tap **Free** / **Get** to install. From then on it updates itself on
  AltStore's background refresh (you can also pull-to-refresh **My Apps**).
- **SideStore:** open SideStore → **Browse** / **Sources** → **＋ Add Source** → paste the same URL → add.

The source always tracks the latest release, so you're one tap from the newest build instead of
hunting for the `.ipa` each time.

> ### Two honest limitations of free-Apple-ID sideloading
> - **7-day expiry.** Apps signed with a *free* Apple ID stop launching after 7 days and need
>   re-signing. **AltStore/SideStore refresh this automatically** in the background — keep the
>   sideloader installed and NOOP keeps working.
> - **Apple-only features require their extensions and capabilities.** Keep the
>   `NOOPWidgets.appex` extension enabled when AltStore/SideStore asks: it renders the Home/Lock-Screen
>   widgets and Live Activities and shares data through the provisioned App Group. Removing app
>   extensions while signing disables those surfaces. Other signing tools must likewise preserve and
>   provision the requested HealthKit and App Group entitlements. Building from source with your own
>   Apple ID in Xcode and selecting your Team for both targets configures them automatically.

The number-crunching (recovery, strain, HRV, sleep) lives in the Swift packages and is mirrored on
Android. Live BLE on a real iPhone is still being validated by the community, so reports
are very welcome.

## Build from source

Run `Tools/ios.sh build` or `Tools/ios.sh test`. Both generate `Strand.xcodeproj` from `project.yml`.
Unit tests run on a local simulator; install the printed `.app` on any other simulator for UI checks.

Prefer to build it yourself (which also grants HealthKit/widgets under your own Apple ID)? Run
`xcodegen generate`, then build the **`NOOPiOS`** scheme in Xcode.

> 🛠️ **Signing it under your own Apple ID** (thanks @gingerbeardman for the original recipe). Apple
> requires a bundle id and app group unique to *your* developer account — otherwise the build collides
> with any other NOOP install already on your device (an AltStore/SideStore sideload, or someone
> else's build). Two steps:
> 1. `cp Config/BundleIdSecrets.example.xcconfig Config/BundleIdSecrets.xcconfig` and set
>    `BUNDLE_ID_PREFIX` to your own reverse-domain prefix (e.g. `com.yourdomain`), then re-run
>    `xcodegen generate`. This one gitignored file drives **every** target's bundle id *and* the shared
>    App Group together (`$(BUNDLE_ID_PREFIX).noop`, `group.$(BUNDLE_ID_PREFIX).noop.staging`) — nothing
>    hard-coded in Swift, nothing else to edit, and it survives future regenerates.
> 2. Set `DEVELOPMENT_TEAM = YOUR_TEAM_ID` in the same local config. All targets inherit it,
>    including the widget extension, and it survives `xcodegen generate`.
>    The matching Apple account must be signed in under Xcode's Settings > Accounts.
>
> Skip step 1 and the build still works under the default `com.noopapp` identifiers — fine if this is
> the only NOOP install on your device.

### Running on iOS 27.0

The existing app can be built with Xcode 26.4.1 and installed on an iOS 27.0
device. Use Xcode 27 when you need the iOS 27 SDK. Apple's
[Xcode requirements](https://developer.apple.com/xcode/system-requirements/) list
the supported macOS versions and SDKs. Xcode 27 RC requires macOS 26.6 or later.
Download it from [Apple Developer Downloads](https://developer.apple.com/download/),
open it to finish setup, then open `Strand.xcodeproj`, select the `NOOPiOS` scheme
and your paired iPhone, and run.

Keep the iOS deployment target at 17.0. This is the oldest supported OS, so it
does not need to become 27.0 to run on an iOS 27 phone. The project uses `iphoneos`
as its SDK setting, which follows the selected Xcode installation.

If Xcode reports that the developer disk image could not be mounted, unlock the
iPhone and keep it awake, then retry. Check the underlying error before updating
Xcode or its platform support. Changing the deployment target does not install
device support. If installation succeeds but launch reports an untrusted profile,
open Settings > General > VPN & Device Management on the iPhone and trust your
developer profile. For command-line builds with
multiple Xcode installations, set `DEVELOPER_DIR` to the intended app's
`Contents/Developer` directory.

> ℹ️ **Cross-platform engineering lives in [`CROSS_PLATFORM.md`](CROSS_PLATFORM.md)** — the shared-code
> boundary across the iOS / Android clients, the `Platform.swift` shim convention, the
> Swift↔Kotlin parity discipline, and the playbook for adding a feature across both. Read that
> first if you're building something that should land on more than one client.

> **Not affiliated with WHOOP.** NOOP is an independent, unofficial project. It is
> not affiliated with, endorsed by, or connected to WHOOP, Inc. "WHOOP" is used
> nominatively only to identify the hardware the app interoperates with — your own
> device and your own data. NOOP performs no DRM circumvention and ships no WHOOP
> proprietary code, firmware, or assets. **NOOP is not a medical device;** all
> metrics (HR, HRV, recovery, strain, sleep, SpO₂, temperature) are approximations
> and not clinically validated.

The reverse-engineering that makes any of this possible is built on prior
community work: the WHOOP 4.0 protocol from **`johnmiddleton12/my-whoop`** and
the WHOOP 5.0 / MG protocol from **`b-nnett/goose`**. See [`../ATTRIBUTION.md`](../ATTRIBUTION.md).
