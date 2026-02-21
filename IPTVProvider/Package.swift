// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "IPTVProvider",
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
    .tvOS(.v26),
  ],
  products: [
    .library(name: "IPTVProvider", targets: ["IPTVProvider"]),
  ],
  dependencies: [
    .package(path: "../SugoiCore"),
  ],
  targets: [
    .target(
      name: "IPTVProvider",
      dependencies: ["SugoiCore"],
      path: "Sources",
      swiftSettings: [
        .swiftLanguageMode(.v6),
      ]
    ),
    .testTarget(
      name: "IPTVProviderTests",
      dependencies: ["IPTVProvider", "SugoiCore"],
      path: "Tests",
      resources: [
        .copy("Fixtures"),
      ]
    ),
  ]
)
