import Foundation
import StrandDesign
import SwiftUI

/// Rules and formatting behind the screens, kept apart from any one interface.
enum StorageFormat {
    /// Human byte size, decimal (matches iOS Settings' "Documents & Data" presentation).
    static func format(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: bytes)
    }
}
