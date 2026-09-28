#if os(iOS)
import SwiftUI
import StrandDesign

/// Account group: settings, devices, data, integrations and app utilities.
struct BroopAccountScreens: View {
    let screen: BroopScreen

    var body: some View {
        switch screen {
        case .settings: SettingsView().broopClassicScreen()
        case .devices: DevicesView().broopClassicScreen()
        case .appleHealth: AppleHealthView().broopClassicScreen()
        case .miBand: XiaomiBandView().broopClassicScreen()
        case .dataSources: DataSourcesView().broopClassicScreen()
        case .backupSync: BackupSyncView().broopClassicScreen()
        case .shortcutsExport: ShortcutExportSettingsView().broopClassicScreen()
        case .noopLimitations: NoopLimitationsView().broopClassicScreen()
        case .automations: AutomationsView().broopClassicScreen()
        case .siriShortcuts: SiriShortcutsSettingsView().broopClassicScreen()
        case .powerSaving: PowerSavingView().broopClassicScreen()
        case .testCentre: TestCentreView().broopClassicScreen()
        case .classicToday: BroopClassicTodayRoot().broopClassicScreen()
        default: EmptyView()
        }
    }
}

/// Classic Today as the wearer configured it (Liquid or the original), like the classic shell's tab.
struct BroopClassicTodayRoot: View {
    @AppStorage("noop.liquidTodayEnabled") private var liquidTodayEnabled = true
    var body: some View {
        if liquidTodayEnabled { LiquidTodayView() } else { TodayView() }
    }
}
#endif
