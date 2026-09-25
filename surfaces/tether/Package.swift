// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "NervePlugin",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "NerveHubClient", targets: ["NerveHubClient"]),
    .library(name: "NervePlugin", targets: ["NervePlugin"]),
  ],
  dependencies: [
    .package(path: "../../../Tether/app/Packages/TetherFrontend"),
    .package(path: "../ribbon"),
  ],
  targets: [
    .target(name: "NerveHubClient"),
    .target(
      name: "NervePlugin",
      dependencies: [
        "NerveHubClient",
        .product(name: "TetherPluginKit", package: "TetherFrontend"),
        .product(name: "NerveRibbonUI", package: "ribbon"),
      ]
    ),
    .testTarget(name: "NerveHubClientTests", dependencies: ["NerveHubClient"]),
  ]
)
