#if os(iOS)
import SwiftUI
import StrandDesign

/// Account group: settings, devices, data, integrations and app utilities. Every screen here is a
/// native Broop view except the developer Test Centre (a diagnostics tool, kept classic under the Broop
/// skin) and Classic Today (the classic dashboard on purpose).
struct BroopAccountScreens: View {
    let screen: BroopScreen

    var body: some View {
        switch screen {
        case .settings: BroopAccountSettingsView()
        case .devices: BroopAccountDeviceView()
        case .appleHealth: BroopAccountAppleHealthView()
        case .miBand: BroopAccountMiBandView()
        case .dataSources: BroopAccountDataSourcesView()
        case .backupSync: BroopAccountBackupSyncView()
        case .shortcutsExport: BroopAccountShortcutsExportView()
        case .noopLimitations: BroopAccountLimitationsView()
        case .automations: BroopAccountAutomationsView()
        case .siriShortcuts: BroopAccountSiriView()
        case .powerSaving: BroopAccountPowerSavingView()
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
