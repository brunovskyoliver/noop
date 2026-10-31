#if os(iOS)
import SwiftUI
import StrandDesign

/// Account group: settings, devices, data, integrations and app utilities. Every screen here is a
/// native Broop view except the developer Test Centre (a diagnostics tool, kept classic under the Broop
/// skin).
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
        default: EmptyView()
        }
    }
}

#endif
