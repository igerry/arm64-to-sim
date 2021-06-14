// swift-tools-version:5.3
import PackageDescription

let package = Package(
  name: "arm64-to-sim",
  platforms: [
    .macOS(.v11),
  ],
  products: [
    .executable(name: "arm64-to-sim", targets: ["arm64-to-sim"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.3"),
  ],
  targets: [
    .target(
      name: "arm64-to-sim",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
  ]
)
