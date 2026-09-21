// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "NervePlugin",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "NerveHubClient", targets: ["NerveHubClient"]),
    .library(name: "NervePlugin", targets: ["NervePlugin"]),
  ],
  dependencies: [
    .package(path: "../../../Tether/app/Packages/TetherFrontend")
  ],
  targets: [
    .target(name: "NerveHubClient"),
    .target(
      name: "NervePlugin",
      dependencies: [
        "NerveHubClient",
        .product(name: "TetherPluginKit", package: "TetherFrontend"),
      ]
    ),
    .testTarget(name: "NerveHubClientTests", dependencies: ["NerveHubClient"]),
  ]
)
