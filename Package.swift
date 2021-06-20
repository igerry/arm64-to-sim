// swift-tools-version:5.4
import PackageDescription

let package = Package(
  name: "arm64-to-sim",
  platforms: [
    .macOS(.v11),
  ],
  products: [
    .library(
      name: "Arm64ToSim",
      targets: ["Arm64ToSim"]
    ),
    .executable(
      name: "arm64-to-sim",
      targets: ["arm64-to-sim"]
    ),
  ],
  targets: [
    .target(
      name: "Arm64ToSim"
    ),
    .executableTarget(
      name: "arm64-to-sim",
      dependencies: [
        .target(name: "Arm64ToSim"),
      ]
    ),
  ]
)
