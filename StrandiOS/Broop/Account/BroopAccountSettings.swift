#if os(iOS)
import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import StrandAnalytics
import StrandDesign
import WhoopStore

// MARK: - App Settings root

/// Broop App Settings: WHOOP-style card rows into native sub-pages. Every control of the classic
/// `SettingsView` is on one of these pages, bound to the same `@AppStorage` keys and stores, with the
/// same side effects (re-score on a recipe change, BLE re-arm on an HRV-capture change, and so on).
struct BroopAccountSettingsView: View {
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(BroopPrefs.enabledKey) private var broopEnabled = true
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountSection(title: String(localized: "Account")) {
                VStack(spacing: BroopAccountStyle.rowGap) {
                    BroopAccountPageLink(symbol: "person.crop.circle", title: String(localized: "Profile Information"),
                                         subtitle: String(localized: "Age \(profile.age) · \(sexLabel)")) {
                        BroopAccountProfilePage()
                    }
                    BroopAccountPageLink(symbol: "heart.circle", title: String(localized: "Heart Rate Zones"),
                                         subtitle: String(localized: "Max HR \(profile.hrMax) bpm")) {
                        BroopAccountHeartRatePage()
                    }
                    BroopAccountPageLink(symbol: "ruler", title: String(localized: "Units"),
                                         subtitle: unitSystemRaw == UnitSystem.imperial.rawValue
                                            ? String(localized: "Imperial") : String(localized: "Metric")) {
                        BroopAccountUnitsPage()
                    }
                }
            }
            BroopAccountSection(title: String(localized: "App")) {
                VStack(spacing: BroopAccountStyle.rowGap) {
                    BroopAccountPageLink(symbol: "bell", title: String(localized: "Notifications")) {
                        BroopAccountNotificationsPage()
                    }
                    BroopAccountPageLink(symbol: "circle.lefthalf.filled", title: String(localized: "Appearance"),
                                         subtitle: String(localized: "Language, clock, theme and colours")) {
                        BroopAccountAppearancePage()
                    }
                    BroopAccountPageLink(symbol: "sparkles", title: String(localized: "Coach & Features")) {
                        BroopAccountFeaturesPage()
                    }
                    BroopAccountPageLink(symbol: "applewatch.side.right", title: String(localized: "Strap & Sync"),
                                         subtitle: String(localized: "Connection, strap log, Live Activities")) {
                        BroopAccountStrapPage()
                    }
                    classicInterfaceCard
                }
            }
            BroopAccountSection(title: String(localized: "Data & Privacy")) {
                VStack(spacing: BroopAccountStyle.rowGap) {
                    BroopAccountPageLink(symbol: "externaldrive", title: String(localized: "Backup & Export"),
                                         subtitle: String(localized: "Back up, restore, export CSV")) {
                        BroopAccountDataPage()
                    }
                    BroopAccountPageLink(symbol: "internaldrive", title: String(localized: "Storage")) {
                        StorageView().broopClassicScreen()
                    }
                }
            }
            BroopAccountSection(title: String(localized: "Advanced")) {
                VStack(spacing: BroopAccountStyle.rowGap) {
                    BroopAccountPageLink(symbol: "slider.horizontal.3", title: String(localized: "Scoring & Recovery"),
                                         subtitle: String(localized: "Charge baseline, HRV capture, sleep staging")) {
                        BroopAccountScoringPage()
                    }
                    BroopAccountPageLink(symbol: "flask", title: String(localized: "Experimental")) {
                        BroopAccountExperimentalPage()
                    }
                    BroopAccountLink(value: BroopScreen.testCentre, symbol: "stethoscope",
                                     title: String(localized: "Developer · Test Centre"),
                                     subtitle: String(localized: "Tests, probes and the bug-report bundle"))
                }
            }
            BroopAccountSection(title: String(localized: "Support")) {
                BroopAccountPageLink(symbol: "info.circle", title: String(localized: "About")) {
                    BroopAccountAboutPage()
                }
            }
        }
        .broopAccountChrome(String(localized: "App Settings"))
    }

    private var sexLabel: String { BroopAccountFormat.sex(profile.sex) }

    private var classicInterface: Binding<Bool> {
        Binding(get: { !broopEnabled }, set: { broopEnabled = !$0 })
    }

    private var classicInterfaceCard: some View {
        BroopAccountGroup {
            BroopAccountToggle(title: String(localized: "Classic NOOP interface"),
                               detail: String(localized: "Use the original five-tab NOOP layout. To return, turn on More → Broop interface."),
                               isOn: classicInterface)
        }
    }
}

enum BroopAccountFormat {
    static func sex(_ raw: String) -> String {
        switch raw {
        case "female": return String(localized: "Female")
        case "nonbinary": return String(localized: "Non-binary")
        default: return String(localized: "Male")
        }
    }
}

// MARK: - Profile

/// Profile Information: photo, body measurements, day boundary and step calibration.
struct BroopAccountProfilePage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var showStepsCalibration = false
    @State private var streak: (current: Int, longest: Int) = (0, 0)

    private var imperial: Bool { (UnitSystem(rawValue: unitSystemRaw) ?? .metric) == .imperial }

    var body: some View {
        BroopAccountPage(spacing: 30) {
            photoHeader
            streakCard
            BroopAccountSection(title: String(localized: "Personal information"),
                                footer: String(localized: "These power your heart-rate zones, calorie estimates and recovery baselines. Keep them accurate.")) {
                BroopAccountGroup {
                    BroopAccountRow(title: String(localized: "Date of birth"), detail: String(localized: "Age \(profile.age)")) {
                        DatePicker("", selection: $profile.dateOfBirth, in: ProfileStore.dateOfBirthRange,
                                   displayedComponents: .date)
                            .labelsHidden()
                            .tint(BroopPalette.teal)
                            .accessibilityLabel(Text("Date of birth, age \(profile.age) years"))
                    }
                    BroopAccountPicker(title: String(localized: "Sex"), selection: $profile.sex, options: [
                        ("male", String(localized: "Male")),
                        ("female", String(localized: "Female")),
                        ("nonbinary", String(localized: "Non-binary")),
                    ])
                    BroopAccountRow(title: String(localized: "Weight")) { weightField }
                    BroopAccountRow(title: String(localized: "Height")) { heightField }
                    BroopAccountRow(title: String(localized: "Waist"),
                                    detail: String(localized: "Optional: VO₂max builds from about 4 nights of heart rate; a waist makes it more accurate. The Fitness Age itself doesn't need it. Measure around your middle, at the navel.")) {
                        waistField
                    }
                }
            }
            BroopAccountSection(title: String(localized: "Your day")) {
                BroopAccountGroup {
                    BroopAccountPicker(
                        title: String(localized: "Day starts"),
                        detail: dayCycleModeRaw == DayCycleMode.midnight.rawValue
                            ? String(localized: "Uses a conventional local calendar day from 00:00 to 00:00.")
                            : String(localized: "Default. Steps and in-progress Effort restart at the beginning of detected main sleep. Naps do not start a new day; missing sleep falls back to local midnight."),
                        selection: dayCycleBinding,
                        options: [(DayCycleMode.sleepOnset, String(localized: "Main sleep")), (DayCycleMode.midnight, "00:00")])
                }
            }
            BroopAccountSection(title: String(localized: "Steps")) {
                BroopAccountGroup {
                    BroopAccountRow(title: String(localized: "Step calibration"),
                                    detail: String(localized: "Counter ticks per step. Leave at 1.0 unless your steps run high. On a WHOOP 5/MG they can run very high (10× or more), so this goes up to 30. Walk a known 1,000 steps and divide NOOP's count by the real count to get your value.")) {
                        BroopAccountStepper(
                            value: String(format: "%.1f", profile.stepTicksPerStep),
                            accessibility: String(localized: "Step calibration, \(String(format: "%.1f", profile.stepTicksPerStep)) counter ticks per step"),
                            onDecrement: { profile.stepTicksPerStep = ProfileStore.steppedStepScale(profile.stepTicksPerStep, up: false) },
                            onIncrement: { profile.stepTicksPerStep = ProfileStore.steppedStepScale(profile.stepTicksPerStep, up: true) })
                    }
                    BroopAccountButtonRow(title: String(localized: "Steps estimate"), value: stepsCalibrationSummary,
                                          detail: String(localized: "For a WHOOP 4.0, which sends no step count: NOOP estimates steps from motion, calibrated to your phone. Tap to see how close it is and adjust it.")) {
                        showStepsCalibration = true
                    }
                }
            }
        }
        .broopAccountChrome(String(localized: "Profile"))
        .sheet(isPresented: $showStepsCalibration) {
            StepsCalibrationSheet(repo: model.repo, onClose: { showStepsCalibration = false })
                .environmentObject(profile)
        }
        .onChange(of: avatarPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data { profile.setAvatar(data) }
                    avatarPickerItem = nil
                }
            }
        }
        .task(id: repo.refreshSeq) {
            let days = repo.days
            let today = AnalyticsEngine.dayString(Int(Date().timeIntervalSince1970),
                                                  offsetSec: TimeZone.current.secondsFromGMT())
            let s = StreakCalculator.streaks(dayKeys: days.map { $0.day },
                                             qualified: days.map { $0.recovery != nil }, today: today)
            streak = (s.current, s.longest)
        }
    }

    private var photoHeader: some View {
        VStack(spacing: 14) {
            ProfileAvatarView(imageData: profile.avatarImageData, size: 96)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .accessibilityLabel(Text(profile.hasAvatar ? "Your profile photo" : "No profile photo set"))
            HStack(spacing: 10) {
                PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                    BroopCaps(profile.hasAvatar ? String(localized: "Change photo") : String(localized: "Choose photo"), size: 11.5)
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.2))
                }
                if profile.hasAvatar {
                    Button { profile.clearAvatar() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.2))
                    }
                    .accessibilityLabel(Text("Remove photo"))
                }
            }
            Text("Optional. It stays on \(Platform.deviceNounPhrase) and is never uploaded.")
                .font(BroopType.regular(12.5))
                .foregroundStyle(BroopAccountStyle.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// Current and longest Charge streak (#569), the same StreakCalculator the classic card used.
    private var streakCard: some View {
        HStack(spacing: 0) {
            streakColumn(value: streak.current, label: String(localized: "Current streak"))
            Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 44)
            streakColumn(value: streak.longest, label: String(localized: "Longest streak"))
        }
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
    }

    private func streakColumn(value: Int, label: String) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: "\(value)")
                    .font(BroopType.number(30))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .broopNumeral(30)
                Text(value == 1 ? "day" : "days")
                    .font(BroopType.medium(13))
                    .foregroundStyle(BroopAccountStyle.caption)
            }
            BroopCaps(label, size: 9.5, color: BroopAccountStyle.caption)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var dayCycleBinding: Binding<DayCycleMode> {
        Binding(
            get: { DayCycleMode.persisted(dayCycleModeRaw) },
            set: { mode in
                dayCycleModeRaw = mode.rawValue
                Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
            })
    }

    private var stepsCalibrationSummary: String {
        if profile.stepsManualCoefficient > 0 { return String(localized: "Manual") }
        if profile.stepsCalibrationCoefficient > 0 {
            return String(localized: "Auto · \(StepsCalibrationFormat.confidenceLabel(profile.stepsCalibrationConfidence)) confidence")
        }
        return String(localized: "Not calibrated")
    }

    // Imperial steps in pounds / whole inches and stores the SI value, exactly as the classic fields do.
    @ViewBuilder private var weightField: some View {
        if imperial {
            let lb = Binding<Double>(
                get: { UnitFormatter.kgToPounds(profile.weightKg) },
                set: { profile.weightKg = $0 / UnitFormatter.poundsPerKilogram })
            BroopAccountStepper(value: lb, in: 66...551, step: 1, text: String(format: "%.0f", lb.wrappedValue),
                                unit: "lb", accessibility: String(localized: "Weight, \(Int(lb.wrappedValue.rounded())) pounds"))
        } else {
            BroopAccountStepper(value: $profile.weightKg, in: 30...250, step: 0.5,
                                text: String(format: "%.1f", profile.weightKg), unit: "kg",
                                accessibility: String(localized: "Weight in kilograms"))
        }
    }

    @ViewBuilder private var heightField: some View {
        if imperial {
            let inches = Binding<Double>(
                get: { UnitFormatter.cmToInches(profile.heightCm).rounded() },
                set: { profile.heightCm = $0 * UnitFormatter.centimetersPerInch })
            let parts = UnitFormatter.cmToFeetInches(profile.heightCm)
            BroopAccountStepper(value: inches, in: 47...91, step: 1, text: "\(parts.feet)′ \(parts.inches)″",
                                accessibility: String(localized: "Height, \(parts.feet) feet \(parts.inches) inches"))
        } else {
            BroopAccountStepper(value: $profile.heightCm, in: 120...230, step: 1,
                                text: String(format: "%.0f", profile.heightCm), unit: "cm",
                                accessibility: String(localized: "Height in centimetres"))
        }
    }

    /// 0 = unset. Stepping up from unset lands near a sensible value; stepping below the floor clears it.
    @ViewBuilder private var waistField: some View {
        let set = profile.waistCm > 0
        if imperial {
            let inches = set ? UnitFormatter.cmToInches(profile.waistCm).rounded() : 0
            BroopAccountStepper(
                value: set ? "\(Int(inches))" : String(localized: "Not set"), unit: set ? "in" : nil, dimmed: !set,
                accessibility: set ? String(localized: "Waist, \(Int(inches)) inches") : String(localized: "Waist not set"),
                canDecrement: set,
                onDecrement: {
                    let nextIn = inches - 1
                    profile.waistCm = nextIn < 24 ? 0 : nextIn * UnitFormatter.centimetersPerInch
                },
                onIncrement: {
                    let nextIn = (set ? inches : 30) + 1
                    profile.waistCm = min(160, nextIn * UnitFormatter.centimetersPerInch)
                })
        } else {
            BroopAccountStepper(
                value: set ? String(format: "%.0f", profile.waistCm) : String(localized: "Not set"),
                unit: set ? "cm" : nil, dimmed: !set,
                accessibility: set ? String(localized: "Waist, \(Int(profile.waistCm.rounded())) centimetres") : String(localized: "Waist not set"),
                canDecrement: set,
                onDecrement: {
                    let next = profile.waistCm - 1
                    profile.waistCm = next < 60 ? 0 : next
                },
                onIncrement: { profile.waistCm = min(160, (set ? profile.waistCm : 79) + 1) })
        }
    }
}

// MARK: - Heart rate zones

/// WHOOP's Heart Rate Settings: a max HR field, the custom-zones switch and the Zone 5 → 1 table.
/// The zones come from `profile.hrZoneSet`, the one model live HR, workout splits and coaching use.
struct BroopAccountHeartRatePage: View {
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        BroopAccountPage(spacing: 28) {
            BroopAccountHeading(
                title: String(localized: "Heart Rate Zones"),
                detail: String(localized: "Your zones are percentages of your maximum heart rate: Zone 1 starts at 50% and Zone 5 at 90%. Max HR comes from your age (Tanaka) unless you set it yourself. Live heart rate, workout splits and haptic coaching all use these zones."))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    BroopCaps(String(localized: "Max HR"), size: 12, color: BroopAccountStyle.caption)
                    Spacer()
                    BroopCaps(profile.hrMaxOverride > 0 ? String(localized: "Manual override")
                                                        : String(localized: "Auto · \(profile.hrMax) bpm (Tanaka)"),
                              size: 10, color: profile.hrMaxOverride > 0 ? BroopPalette.teal : BroopAccountStyle.caption)
                }
                HStack(spacing: 12) {
                    BroopAccountStepper(
                        value: profile.hrMaxOverride > 0 ? "\(profile.hrMaxOverride)" : String(localized: "Auto"),
                        unit: "bpm", dimmed: profile.hrMaxOverride == 0,
                        accessibility: String(localized: "Max heart rate override, \(profile.hrMaxOverride == 0 ? String(localized: "automatic") : "\(profile.hrMaxOverride) bpm")"),
                        canDecrement: profile.hrMaxOverride > 0,
                        canIncrement: profile.hrMaxOverride < 230,
                        onDecrement: { profile.hrMaxOverride = max(0, profile.hrMaxOverride - 1) },
                        onIncrement: { profile.hrMaxOverride = min(230, profile.hrMaxOverride + 1) })
                    Spacer(minLength: 0)
                    if profile.hrMaxOverride > 0 {
                        Button { profile.hrMaxOverride = 0 } label: {
                            BroopCaps(String(localized: "Use auto"), size: 11)
                        }
                        .buttonStyle(BroopPressableStyle())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Custom Heart Rate Zones")
                        .font(BroopType.demi(19))
                        .foregroundStyle(BroopPalette.textPrimary)
                    Spacer()
                    Toggle("", isOn: Binding(get: { profile.hasCustomHRZones },
                                             set: { profile.setCustomHRZonesEnabled($0) }))
                        .labelsHidden()
                        .tint(BroopPalette.teal)
                        .accessibilityLabel(Text("Custom HR zones"))
                }
                Text(profile.hasCustomHRZones
                     ? "Set the BPM where each zone begins. Turn off to restore the default percentage-of-max zones."
                     : "Turn on to set the BPM where each zone begins, if the default zones don't feel right for you.")
                    .font(BroopType.regular(15))
                    .foregroundStyle(BroopAccountStyle.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            zoneTable
        }
        .broopAccountChrome(String(localized: "Heart Rate Settings"))
    }

    private var zoneTable: some View {
        let zones = profile.hrZoneSet.zones.sorted { $0.number > $1.number }
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                BroopCaps(String(localized: "Zone"), size: 10.5, color: BroopAccountStyle.caption)
                    .frame(width: 84, alignment: .leading)
                BroopCaps(profile.hasCustomHRZones ? String(localized: "Starts at") : String(localized: "Zone min"),
                          size: 10.5, color: BroopAccountStyle.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                BroopCaps(String(localized: "Zone max"), size: 10.5, color: BroopAccountStyle.caption)
                    .frame(width: 92, alignment: .leading)
            }
            .padding(.leading, 14)
            ForEach(zones, id: \.number) { zone in
                zoneRow(zone)
            }
        }
    }

    private func zoneRow(_ zone: HRZone) -> some View {
        let tint = Self.zoneColor(zone.number)
        let index = zone.number - 1
        return HStack(spacing: 10) {
            Text("Zone \(zone.number)")
                .font(BroopType.demi(17))
                .foregroundStyle(BroopPalette.textPrimary)
                .frame(width: 84, alignment: .leading)
                .padding(.leading, 14)
            Group {
                if profile.hasCustomHRZones, profile.hrZoneThresholds.indices.contains(index) {
                    BroopAccountStepper(
                        value: "\(profile.hrZoneThresholds[index])", unit: "bpm",
                        accessibility: String(localized: "Zone \(zone.number) starts at \(profile.hrZoneThresholds[index]) beats per minute"),
                        onDecrement: { profile.stepHRZoneThreshold(at: index, up: false) },
                        onIncrement: { profile.stepHRZoneThreshold(at: index, up: true) })
                } else {
                    field("\(Int(zone.lower))")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            field("\(Int(zone.upper))")
                .frame(width: 92, alignment: .leading)
        }
        .frame(height: 56)
        .background(
            LinearGradient(colors: [tint.opacity(0.22), .clear], startPoint: .leading, endPoint: .init(x: 0.45, y: 0.5))
        )
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
        .accessibilityElement(children: .combine)
    }

    private func field(_ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: value)
                .font(BroopType.number(19))
                .foregroundStyle(BroopPalette.textSecondary)
            Spacer(minLength: 4)
            Text("bpm").font(BroopType.medium(13)).foregroundStyle(BroopPalette.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BroopAccountStyle.field.opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    /// Zone edge colours from the WHOOP reference: red-orange, orange, green, blue, grey.
    static func zoneColor(_ number: Int) -> Color {
        switch number {
        case 5: return Color(broopHex: 0xF0522B)
        case 4: return Color(broopHex: 0xF5A332)
        case 3: return Color(broopHex: 0x3CC98B)
        case 2: return Color(broopHex: 0x3D95D8)
        default: return Color(broopHex: 0xA3A8AC)
        }
    }
}

// MARK: - Units

struct BroopAccountUnitsPage: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinTempDisplayRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(PuffinExperiment.banisterEffortKey) private var banisterEffortEnabled = false

    private var distanceBinding: Binding<String> {
        Binding(get: { UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric,
                                                 override: distanceSystemRaw).rawValue },
                set: { distanceSystemRaw = $0 })
    }

    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountHeading(title: String(localized: "Units"),
                                detail: String(localized: "Choose body measurements and exercise distance separately. Your data is always stored the same way; these settings only change its display."))
            BroopAccountSection(title: String(localized: "Measurements")) {
                BroopAccountGroup {
                    BroopAccountPicker(title: String(localized: "Body measurements"), selection: $unitSystemRaw, options: [
                        (UnitSystem.metric.rawValue, String(localized: "Metric")),
                        (UnitSystem.imperial.rawValue, String(localized: "Imperial")),
                    ])
                    BroopAccountPicker(title: String(localized: "Exercise distance & pace"), selection: distanceBinding, options: [
                        (UnitSystem.metric.rawValue, String(localized: "Kilometres")),
                        (UnitSystem.imperial.rawValue, String(localized: "Miles")),
                    ])
                    BroopAccountPicker(title: String(localized: "Temperature"), selection: $temperatureRaw, options: [
                        ("", String(localized: "Follow body")),
                        (TemperatureUnit.celsius.rawValue, "°C"),
                        (TemperatureUnit.fahrenheit.rawValue, "°F"),
                    ])
                    BroopAccountPicker(title: String(localized: "Skin temperature"), selection: $skinTempDisplayRaw, options: [
                        ("", String(localized: "Temperature")),
                        (SkinTempDisplay.Kind.deviation.rawValue, String(localized: "vs baseline")),
                    ])
                }
            }
            BroopAccountSection(title: String(localized: "Effort")) {
                BroopAccountGroup {
                    BroopAccountPicker(title: String(localized: "Effort scale"),
                                       detail: String(localized: "Show Effort on NOOP's 0–100 axis or the 0–21 Day Strain axis. Display only; the stored value never changes."),
                                       selection: $effortScaleRaw, options: [
                        (EffortScale.hundred.rawValue, "0-100"),
                        (EffortScale.whoop.rawValue, "0-21"),
                    ])
                    BroopAccountToggle(title: String(localized: "Effort: exponential intensity scale"),
                                       detail: String(localized: "Scores Effort on an exponential intensity curve (Banister TRIMP) instead of the default heart-rate zones (Edwards). The default earns nothing below half of your heart-rate reserve, so an hour of lifting — where hard sets average out against the rests — can score close to zero. The exponential curve has no floor and weights short, hard efforts far more heavily. Re-scores your history, and both scales reach the same maximum. Off by default."),
                                       isOn: $banisterEffortEnabled)
                }
            }
        }
        .broopAccountChrome(String(localized: "Units"))
        .onChange(of: banisterEffortEnabled) { _, _ in
            // Re-score immediately: the recipe changes stored Effort for every day in the window.
            Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
        }
    }
}

// MARK: - Appearance

struct BroopAccountAppearancePage: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.system.rawValue
    @AppStorage(ClockFormatPreference.defaultsKey) private var clockFormatRaw = ClockFormatPreference.system.rawValue
    @AppStorage("noop.bottomBarAutoHide") private var bottomBarAutoHide = false
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(ChartStyle.storageKey) private var chartStyleRaw = ChartStyle.titanium.rawValue
    @AppStorage(SleepChartStyle.storageKey) private var sleepChartStyleRaw = SleepChartStyle.classic.rawValue
    @AppStorage(AccentColor.storageKey) private var accentRaw = AccentColor.mint.rawValue
    @AppStorage(AccentColor.customHexKey) private var accentCustomHex = AccentColor.defaultCustomHex
    @AppStorage(UnitPrefs.trendChartStyleKey) private var trendChartStyleRaw = TrendChartStyle.line.rawValue
    @AppStorage("appIcon.alt") private var useNavyIcon = false
    @AppStorage(QuietMotionPrefs.enabledKey) private var quietMotion = false
    @AppStorage(SceneBackgroundPrefs.enabledKey) private var showDayCycleBackground = true
    @AppStorage(SkyBehindCardsPrefs.enabledKey) private var skyBehindCards = true
    @AppStorage(CardAppearancePrefs.opacityKey) private var cardOpacityPercent = CardAppearancePrefs.defaultPercent
    @ObservedObject private var backgroundStore = BackgroundImageStore.shared
    @State private var backgroundPickerItem: PhotosPickerItem?
    @State private var showBackgroundFileImporter = false
    @State private var iconError: String?

    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountSection(title: String(localized: "Language & clock"),
                                footer: String(localized: "Language changes take effect after you reopen NOOP.")) {
                BroopAccountGroup {
                    BroopAccountPicker(title: String(localized: "Language"), selection: $appLanguageRaw,
                                       options: AppLanguage.allCases.map {
                                           ($0.rawValue, $0 == .system ? String(localized: "System default") : $0.autonym)
                                       })
                    BroopAccountPicker(title: String(localized: "Clock"), selection: $clockFormatRaw, options: [
                        (ClockFormatPreference.system.rawValue, String(localized: "System default")),
                        (ClockFormatPreference.twelveHour.rawValue, String(localized: "12-hour")),
                        (ClockFormatPreference.twentyFourHour.rawValue, String(localized: "24-hour")),
                    ])
                }
            }
            if #available(iOS 26.0, *) {
                BroopAccountSection(title: String(localized: "Navigation")) {
                    BroopAccountGroup {
                        BroopAccountToggle(title: String(localized: "Hide bar when scrolling"), isOn: $bottomBarAutoHide)
                    }
                }
            }
            BroopAccountSection(title: String(localized: "Classic screens"),
                                footer: String(localized: "Broop screens are always dark. These choices style the classic NOOP screens and the parts of the app that still use them.")) {
                BroopAccountGroup {
                    BroopAccountPicker(title: String(localized: "Preset"), selection: themePresetBinding,
                                       options: ThemePreset.allCases.map { ($0, $0.label) })
                    BroopAccountPicker(title: String(localized: "Theme"), selection: $appearanceRaw,
                                       options: AppearanceMode.allCases.map { ($0.rawValue, $0.label) })
                    BroopAccountPicker(title: String(localized: "Chart colours"), selection: $chartStyleRaw,
                                       options: ChartStyle.allCases.map { ($0.rawValue, $0.label) })
                    BroopAccountPicker(title: String(localized: "Sleep chart"), selection: $sleepChartStyleRaw,
                                       options: SleepChartStyle.allCases.map { ($0.rawValue, $0.label) })
                    BroopAccountPicker(title: String(localized: "Accent"), selection: $accentRaw,
                                       options: AccentColor.allCases.map { ($0.rawValue, $0.label) })
                    if AccentColor.resolve(accentRaw) == .custom {
                        BroopAccountRow(title: String(localized: "Custom colour")) {
                            ColorPicker("", selection: customAccentBinding, supportsOpacity: false)
                                .labelsHidden()
                                .accessibilityLabel(Text("Custom accent colour"))
                        }
                    }
                    BroopAccountPicker(title: String(localized: "Trend charts"), selection: $trendChartStyleRaw,
                                       options: TrendChartStyle.allCases.map { ($0.rawValue, $0.label) })
                }
            }
            BroopAccountSection(title: String(localized: "App icon")) {
                BroopAccountGroup {
                    BroopAccountPicker(title: String(localized: "App icon"), selection: $useNavyIcon, options: [
                        (false, String(localized: "Default")),
                        (true, String(localized: "Navy")),
                    ])
                }
            }
            BroopAccountSection(title: String(localized: "Motion & backdrop")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Reduce motion in NOOP"),
                                       detail: String(localized: "Holds the liquid gauges, the sky and the tilt response still, and turns off the motion sensor that drives them. Saves battery. Low Power Mode and the system Reduce Motion setting already do this."),
                                       isOn: $quietMotion)
                    BroopAccountToggle(title: String(localized: "Day-cycle background"),
                                       detail: String(localized: "Shows a soft sunrise, day, dusk and night scene behind the Today screen. Turn it off for a plain dark canvas. Your cards stay exactly as readable."),
                                       isOn: $showDayCycleBackground)
                    BroopAccountToggle(title: String(localized: "Sky behind cards"),
                                       detail: String(localized: "Extends the sky behind the whole Today screen, so lowering Card transparency lets it show through every card. Needs the day-cycle background on."),
                                       isOn: $skyBehindCards, enabled: showDayCycleBackground)
                    BroopAccountToggle(title: String(localized: "Transparent cards"),
                                       detail: String(localized: "Let the background show through every card. Tune how much just below."),
                                       isOn: Binding(
                                           get: { cardOpacityPercent < 100 },
                                           set: { on in cardOpacityPercent = on ? (cardOpacityPercent >= 100 ? 70 : cardOpacityPercent) : 100 }))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Card transparency").font(BroopType.demi(15.5)).foregroundStyle(BroopPalette.textPrimary)
                            Spacer()
                            Text(verbatim: "\(100 - cardOpacityPercent)%")
                                .font(BroopType.number(16)).foregroundStyle(BroopPalette.teal)
                        }
                        Slider(value: Binding(get: { Double(100 - cardOpacityPercent) },
                                              set: { cardOpacityPercent = 100 - Int($0.rounded()) }),
                               in: 0...100, step: 1)
                            .tint(BroopPalette.teal)
                        Text("How see-through the cards (Heart Rate, Key Metrics, Recovery Vitals, …) are. Left = solid, right = clear.")
                            .font(BroopType.regular(13)).foregroundStyle(BroopAccountStyle.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
            }
            BroopAccountSection(title: String(localized: "Custom background"),
                                footer: String(localized: "Optional. Use your own photo behind every tab, in place of the day-cycle sky. It stays on \(Platform.deviceNounPhrase) and is never uploaded. Pair it with Transparent cards above to let it show through.")) {
                backgroundControls
            }
        }
        .broopAccountChrome(String(localized: "Appearance"))
        .onChange(of: appLanguageRaw) { _, value in AppLanguage.apply(value) }
        .onChange(of: clockFormatRaw) { _, _ in AppClock.invalidate() }
        .onChange(of: useNavyIcon) { _, value in applyAppIcon(value) }
        .onChange(of: backgroundPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data { backgroundStore.setImage(from: data) }
                    backgroundPickerItem = nil
                }
            }
        }
        .fileImporter(isPresented: $showBackgroundFileImporter, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { backgroundStore.setImage(from: data) }
        }
        .alert("Couldn't change the app icon", isPresented: Binding(get: { iconError != nil }, set: { if !$0 { iconError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(verbatim: iconError ?? "")
        }
    }

    @ViewBuilder private var backgroundControls: some View {
        let hasImage = backgroundStore.hasImage
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $backgroundPickerItem, matching: .images) {
                    BroopCaps(hasImage ? String(localized: "Replace from Photos") : String(localized: "Choose from Photos"), size: 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.2))
                }
                Button { showBackgroundFileImporter = true } label: {
                    BroopCaps(String(localized: "Browse files"), size: 11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.2))
                }
                .buttonStyle(BroopPressableStyle())
            }
            if hasImage {
                if !backgroundStore.recents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        BroopCaps(String(localized: "Recent"), size: 10, color: BroopAccountStyle.caption)
                        HStack(spacing: 10) {
                            ForEach(backgroundStore.recents.indices, id: \.self) { index in
                                recentThumb(index: index)
                            }
                        }
                    }
                }
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Show custom background"), isOn: $backgroundStore.enabled)
                    BroopAccountPicker(title: String(localized: "Scaling"),
                                       selection: Binding(get: { backgroundStore.fillMode },
                                                          set: { backgroundStore.setFillMode($0) }),
                                       options: BackgroundFillMode.allCases.map { ($0, $0.label) })
                    BroopAccountButtonRow(title: String(localized: "Remove image"), titleColor: BroopAccountStyle.danger,
                                          showsChevron: false) {
                        backgroundStore.clearImage()
                    }
                }
            }
        }
    }

    private func recentThumb(index: Int) -> some View {
        let active = index == 0
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button { backgroundStore.applyRecent(index) } label: {
            VStack(spacing: 4) {
                Group {
                    if backgroundStore.thumbnails.indices.contains(index), let thumb = backgroundStore.thumbnails[index] {
                        thumb.resizable().scaledToFill()
                    } else {
                        BroopAccountStyle.field
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(shape)
                .overlay(shape.strokeBorder(active ? BroopPalette.teal : BroopPalette.hairline, lineWidth: active ? 2 : 1))
                Text(verbatim: backgroundStore.recents[index].fillMode.label)
                    .font(BroopType.medium(11))
                    .foregroundStyle(active ? BroopPalette.teal : BroopAccountStyle.caption)
            }
        }
        .buttonStyle(.plain)
    }

    private var customAccentBinding: Binding<Color> {
        Binding(get: { Color(hex: accentCustomHex) },
                set: { accentCustomHex = BroopAccountFormat.hex($0) ?? AccentColor.defaultCustomHex })
    }

    /// The preset is derived from the four coordinated prefs; picking one writes all four.
    private var themePresetBinding: Binding<ThemePreset> {
        Binding(
            get: {
                ThemePreset.matching(accent: AccentColor.resolve(accentRaw), chart: ChartStyle.resolve(chartStyleRaw),
                                     backdrop: showDayCycleBackground, cardOpacity: cardOpacityPercent)
            },
            set: { preset in
                guard let r = preset.recipe else { return }
                accentRaw = r.accent.rawValue
                chartStyleRaw = r.chart.rawValue
                showDayCycleBackground = r.backdrop
                cardOpacityPercent = r.cardOpacity
            })
    }

    /// Same as the classic control: skip no-op requests, revert the picker if iOS refuses.
    private func applyAppIcon(_ useNavy: Bool) {
        Task { @MainActor in
            let target = useNavy ? "AppIcon-Navy" : nil
            guard UIApplication.shared.supportsAlternateIcons,
                  UIApplication.shared.alternateIconName != target else { return }
            do {
                try await UIApplication.shared.setAlternateIconName(target)
            } catch {
                useNavyIcon = !useNavy
                iconError = error.localizedDescription
            }
        }
    }
}

extension BroopAccountFormat {
    /// sRGB `#RRGGBB` for the custom accent colour, matching the classic bridge.
    static func hex(_ color: Color) -> String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
#endif
