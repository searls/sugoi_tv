// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "SugoiCore",
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
    .tvOS(.v26),
  ],
  products: [
    .library(name: "SugoiCore", targets: ["SugoiCore"]),
  ],
  targets: [
    .target(
      name: "SugoiCore",
      path: "Sources",
      swiftSettings: [
        .swiftLanguageMode(.v6),
      ]
    ),
    .testTarget(
      name: "SugoiCoreTests",
      dependencies: ["SugoiCore"],
      path: "Tests"
    ),
  ]
)
