// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "YoiTVProvider",
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
    .tvOS(.v26),
  ],
  products: [
    .library(name: "YoiTVProvider", targets: ["YoiTVProvider"]),
  ],
  dependencies: [
    .package(path: "../SugoiCore"),
  ],
  targets: [
    .target(
      name: "YoiTVProvider",
      dependencies: ["SugoiCore"],
      path: "Sources",
      swiftSettings: [
        .swiftLanguageMode(.v6),
      ]
    ),
    .testTarget(
      name: "YoiTVProviderTests",
      dependencies: ["YoiTVProvider", "SugoiCore"],
      path: "Tests"
    ),
  ]
)
