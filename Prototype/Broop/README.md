# Broop prototype

Clickable SwiftUI prototype of a WHOOP-style redesign of the NOOP iOS app: the Today screen,
one detail template (Rest / Charge / Effort), a Health tab and a trimmed More tab.
Sample data only; nothing here reads the NOOP database or talks to a strap. Dark only.

Styling was measured from WHOOP reference screenshots: slate gradient canvas, `#21282C` cards,
`#32383C` row tiles, 5.5 pt flat-ended dials without glow, DIN Alternate Bold numerals and Avenir Next
text (both ship with iOS). The tab bar is the native iOS 26 Liquid Glass one, as in NOOP.

```bash
cd Prototype/Broop
xcodegen generate
open BroopPrototype.xcodeproj   # run the BroopPrototype scheme on an iPhone simulator
```

Regenerate the app icon after changing the `B` geometry (kept in sync with `BrandMark`):

```bash
swift Tools/render_icon.swift Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

| File | Contents |
|---|---|
| `Sources/Theme.swift` | Colour, type, spacing and radius tokens; `ScoreKind` |
| `Sources/Components.swift` | `BrandMark`, `ScoreDial`, `Card`, `RangeBar`, `ContributorRow`, `EffortTargetBar`, `DateNavigator`, `PillSegments` |
| `Sources/TodayView.swift` | Today: header, dials, today's call, My Day, dashboard, health strip; Coach sheet |
| `Sources/ScoreDetailView.swift` | Detail template, trend chart (W / M / 6M), stages, zones |
| `Sources/HealthAndMore.swift` | Health and More tabs |
| `Sources/Store.swift`, `SampleData.swift` | Deterministic sample history and 30-day baselines |
