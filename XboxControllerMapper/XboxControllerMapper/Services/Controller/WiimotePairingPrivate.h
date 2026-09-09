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

#endif /* WiimotePairingPrivate_h */
