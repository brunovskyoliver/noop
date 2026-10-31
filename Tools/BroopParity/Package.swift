// swift-tools-version:5.9
import PackageDescription

// Generates the literal Swift oracle in BroopStressRestParityTest.kt.
let package = Package(
    name: "BroopParityOracle", platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../Packages/StrandAnalytics"), .package(path: "../../Packages/WhoopProtocol")],
    targets: [.executableTarget(name: "Oracle", dependencies: [
        .product(name: "StrandAnalytics", package: "StrandAnalytics"),
        .product(name: "WhoopProtocol", package: "WhoopProtocol"),
    ])]
)
