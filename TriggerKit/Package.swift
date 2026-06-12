// swift-tools-version: 5.9

import PackageDescription

let package = Package(
	name: "TriggerKit",
	platforms: [
		.macOS(.v14)
	],
	products: [
		.library(name: "TriggerKitCore", targets: ["TriggerKitCore"]),
		.library(name: "TriggerKitLibrary", targets: ["TriggerKitLibrary"]),
		.library(name: "TriggerKitRuntime", targets: ["TriggerKitRuntime"]),
		.library(name: "TriggerKitUI", targets: ["TriggerKitUI"])
	],
	targets: [
		.target(name: "TriggerKitCore"),
		.target(name: "TriggerKitLibrary", dependencies: ["TriggerKitCore"]),
		.target(name: "TriggerKitRuntime", dependencies: ["TriggerKitCore"]),
		.target(name: "TriggerKitUI", dependencies: ["TriggerKitCore", "TriggerKitLibrary"]),
		.testTarget(name: "TriggerKitCoreTests", dependencies: ["TriggerKitCore"]),
		.testTarget(name: "TriggerKitLibraryTests", dependencies: ["TriggerKitLibrary"]),
		.testTarget(name: "TriggerKitRuntimeTests", dependencies: ["TriggerKitRuntime"])
	]
)
