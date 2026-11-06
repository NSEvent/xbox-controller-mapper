//
//  WiimotePairingPrivate.h
//  XboxControllerMapper
//
//  Private IOBluetooth APIs required to pair a Nintendo Wii Remote on modern
//  macOS. The remote demands a legacy Bluetooth 2.0 PIN whose value is the
//  host's BT address as six raw (untypeable) bytes, and bluetoothd ignores
//  the public replyPINCode() path since ~Monterey. Approach proven by
//  dolphin-emu/WiimotePair and gdemontalivet/wiimacmote.
//

#ifndef WiimotePairingPrivate_h
#define WiimotePairingPrivate_h

#import <IOBluetooth/IOBluetooth.h>
#import <objc/message.h>
#import <dlfcn.h>

@interface IOBluetoothDevice (WiimotePairingPrivate)
- (id)classicPeer;
@end

@interface IOBluetoothDevicePair (WiimotePairingPrivate)
- (void)setUserDefinedPincode:(BOOL)enabled;
- (NSUInteger)currentPairingType;
@end

@interface IOBluetoothCoreBluetoothCoordinator : NSObject
+ (IOBluetoothCoreBluetoothCoordinator *)sharedInstance;
- (void)pairPeer:(id)peer forType:(NSUInteger)type withKey:(NSNumber *)key;
@end

// System Settings connects services through BluetoothManager. openConnection
// only creates the baseband link and can race the post-pairing disconnect.
// Resolve private selectors at runtime so an OS change fails gracefully.
static inline BOOL CKConnectWiiHIDDevice(NSString *address) {
	static void *framework;
	if (!framework) {
		framework = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_LAZY);
	}
	Class managerClass = NSClassFromString(@"BluetoothManager");
	SEL shared = NSSelectorFromString(@"sharedInstance");
	SEL find = NSSelectorFromString(@"deviceFromAddressString:");
	SEL connect = NSSelectorFromString(@"connectDevice:");
	if (!framework || ![managerClass respondsToSelector:shared]) return NO;
	id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, shared);
	if (![manager respondsToSelector:find] || ![manager respondsToSelector:connect]) return NO;
	id device = ((id (*)(id, SEL, id))objc_msgSend)(manager, find, address);
	if (!device) return NO;
	((void (*)(id, SEL, id))objc_msgSend)(manager, connect, device);
	return YES;
}

#endif /* WiimotePairingPrivate_h */
