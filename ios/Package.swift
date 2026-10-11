// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FuelFormCore", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name: "FuelFormCore", targets: ["FuelFormCore"])], targets: [.target(name: "FuelFormCore", path: "FuelForm/Core"), .executableTarget(name: "FuelFormCoreChecks", dependencies: ["FuelFormCore"], path: "Tests/Core")])
