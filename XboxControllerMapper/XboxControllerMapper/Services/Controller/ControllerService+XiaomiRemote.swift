import Foundation

@MainActor
extension ControllerService {
	var isXiaomiRemoteActiveInputSource: Bool {
		isXiaomiRemoteConnected && controllerName == XiaomiRemoteIdentity.displayName
			&& controllerMappingSource == XiaomiRemoteIdentity.displayName
	}

	func publishXiaomiRemoteConnection() {
		guard !hasActiveHardwareInputSource else { return }
		withStorageLock {
			$0.applyControllerTypeLocked(.xbox)
			$0.eightBitDoModel = nil
		}
		controllerName = XiaomiRemoteIdentity.displayName
		controllerMappingSource = XiaomiRemoteIdentity.displayName
		currentControllerIdentity = xiaomiRemoteIdentity
		isConnected = true
		if !AppRuntime.isRunningTests { startDisplayUpdateTimer() }
	}
}
