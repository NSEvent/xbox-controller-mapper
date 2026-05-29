#import "AppleTVRemoteMultitouch.h"

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int unknown1;
    int unknown2;
    float normalizedVectorPosition[2];
    float normalizedPosition[2];
    float size;
    int zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    float unknown3[2];
} CKMTFinger;

typedef void *CKMTDeviceRef;
typedef int (*CKMTContactCallbackFunction)(int, CKMTFinger *, int, double, int);
typedef CFArrayRef (*CKMTDeviceCreateListFunction)(void);
typedef void (*CKMTRegisterContactFrameCallbackFunction)(CKMTDeviceRef, CKMTContactCallbackFunction);
typedef void (*CKMTUnregisterContactFrameCallbackFunction)(CKMTDeviceRef, CKMTContactCallbackFunction);
typedef void (*CKMTDeviceStartFunction)(CKMTDeviceRef, int);
typedef void (*CKMTDeviceStopFunction)(CKMTDeviceRef);
typedef io_service_t (*CKMTDeviceGetServiceFunction)(CKMTDeviceRef);

static void *gFrameworkHandle;
static CKMTDeviceCreateListFunction gCreateList;
static CKMTRegisterContactFrameCallbackFunction gRegisterCallback;
static CKMTUnregisterContactFrameCallbackFunction gUnregisterCallback;
static CKMTDeviceStartFunction gStartDevice;
static CKMTDeviceStopFunction gStopDevice;
static CKMTDeviceGetServiceFunction gGetService;

static NSArray *gDeviceList;
static NSMutableArray<NSValue *> *gStartedDevices;
static CKAppleTVRemoteMultitouchCallback gTouchCallback;
static void *gTouchContext;

static BOOL CKAppleTVRemoteMultitouchLoadSymbols(void) {
    if (gFrameworkHandle != NULL) {
        return YES;
    }

    gFrameworkHandle = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_LAZY
    );
    if (gFrameworkHandle == NULL) {
        return NO;
    }

    gCreateList = (CKMTDeviceCreateListFunction)dlsym(gFrameworkHandle, "MTDeviceCreateList");
    gRegisterCallback = (CKMTRegisterContactFrameCallbackFunction)dlsym(gFrameworkHandle, "MTRegisterContactFrameCallback");
    gUnregisterCallback = (CKMTUnregisterContactFrameCallbackFunction)dlsym(gFrameworkHandle, "MTUnregisterContactFrameCallback");
    gStartDevice = (CKMTDeviceStartFunction)dlsym(gFrameworkHandle, "MTDeviceStart");
    gStopDevice = (CKMTDeviceStopFunction)dlsym(gFrameworkHandle, "MTDeviceStop");
    gGetService = (CKMTDeviceGetServiceFunction)dlsym(gFrameworkHandle, "MTDeviceGetService");

    return gCreateList != NULL
        && gRegisterCallback != NULL
        && gUnregisterCallback != NULL
        && gStartDevice != NULL
        && gStopDevice != NULL
        && gGetService != NULL;
}

static BOOL CKAppleTVRemoteMultitouchIsRemoteDevice(CKMTDeviceRef device) {
    io_service_t service = gGetService(device);
    if (service == IO_OBJECT_NULL) {
        return NO;
    }

    CFMutableDictionaryRef properties = NULL;
    kern_return_t result = IORegistryEntryCreateCFProperties(
        service,
        &properties,
        kCFAllocatorDefault,
        0
    );
    if (result != KERN_SUCCESS || properties == NULL) {
        return NO;
    }

    NSDictionary *dictionary = CFBridgingRelease(properties);
    NSNumber *productID = dictionary[@"ProductID"];
    NSString *transport = dictionary[@"Transport"];
    NSNumber *familyID = dictionary[@"Family ID"];
    NSNumber *circularSensor = dictionary[@"CircularSensor"];
    NSNumber *columns = dictionary[@"Sensor Columns"];
    NSNumber *rows = dictionary[@"Sensor Rows"];

    NSSet<NSNumber *> *knownProductIDs = [NSSet setWithObjects:@614, @621, @788, @789, nil];
    return [knownProductIDs containsObject:productID]
        && [transport isEqualToString:@"Bluetooth Low Energy"]
        && ([familyID integerValue] == 145 || [circularSensor boolValue])
        && [columns integerValue] == 6
        && [rows integerValue] == 12;
}

static int CKAppleTVRemoteMultitouchContactCallback(
    int deviceID,
    CKMTFinger *fingers,
    int fingerCount,
    double timestamp,
    int frame
) {
    (void)deviceID;
    (void)timestamp;
    (void)frame;

    CKAppleTVRemoteMultitouchCallback callback = gTouchCallback;
    if (callback == NULL) {
        return 0;
    }

    for (int index = 0; index < fingerCount; index++) {
        CKMTFinger finger = fingers[index];
        float x = finger.normalizedVectorPosition[0];
        float y = finger.normalizedVectorPosition[1];
        BOOL validTouch = finger.state > 0
            && finger.size > 0.0f
            && x >= 0.0f && x <= 1.0f
            && y >= 0.0f && y <= 1.0f;

        if (validTouch) {
            callback(gTouchContext, x * 2.0f - 1.0f, y * 2.0f - 1.0f, true);
            return 0;
        }
    }

    callback(gTouchContext, 0.0f, 0.0f, false);
    return 0;
}

bool CKAppleTVRemoteMultitouchStart(void *context, CKAppleTVRemoteMultitouchCallback callback) {
    if (!CKAppleTVRemoteMultitouchLoadSymbols() || callback == NULL) {
        return false;
    }

    if (gStartedDevices.count > 0) {
        gTouchContext = context;
        gTouchCallback = callback;
        return true;
    }

    CFArrayRef devices = gCreateList();
    if (devices == NULL) {
        return false;
    }

    gDeviceList = CFBridgingRelease(devices);
    gStartedDevices = [NSMutableArray array];
    gTouchContext = context;
    gTouchCallback = callback;

    for (id object in gDeviceList) {
        CKMTDeviceRef device = (__bridge CKMTDeviceRef)object;
        if (!CKAppleTVRemoteMultitouchIsRemoteDevice(device)) {
            continue;
        }

        gRegisterCallback(device, CKAppleTVRemoteMultitouchContactCallback);
        gStartDevice(device, 0);
        [gStartedDevices addObject:[NSValue valueWithPointer:device]];
    }

    if (gStartedDevices.count == 0) {
        gTouchContext = NULL;
        gTouchCallback = NULL;
        gDeviceList = nil;
        gStartedDevices = nil;
        return false;
    }

    return true;
}

void CKAppleTVRemoteMultitouchStop(void) {
    if (gStartedDevices.count == 0) {
        gTouchContext = NULL;
        gTouchCallback = NULL;
        return;
    }

    for (NSValue *value in gStartedDevices) {
        CKMTDeviceRef device = [value pointerValue];
        gUnregisterCallback(device, CKAppleTVRemoteMultitouchContactCallback);
        gStopDevice(device);
    }

    gStartedDevices = nil;
    gDeviceList = nil;
    gTouchContext = NULL;
    gTouchCallback = NULL;
}

bool CKAppleTVRemoteMultitouchIsRunning(void) {
    return gStartedDevices.count > 0;
}
