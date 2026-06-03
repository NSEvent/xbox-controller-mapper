#include <CoreAudio/AudioServerPlugIn.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stddef.h>
#include <string.h>

#include "ControllerKeysRemoteMicRingReader.h"

enum {
    kObjectPlugIn = kAudioObjectPlugInObject,
    kObjectDevice = 2,
    kObjectStreamInput = 3,
    kObjectBox = 4
};

#define DEVICE_UID "com.kevintang.ControllerKeys.RemoteMic"
#define MODEL_UID "com.kevintang.ControllerKeys.RemoteMic.Model"
#define BOX_UID "com.kevintang.ControllerKeys.RemoteMic.Box"
#define SAMPLE_RATE ((Float64)CK_REMOTE_MIC_SAMPLE_RATE)
#define CHANNELS CK_REMOTE_MIC_CHANNELS
#define BYTES_PER_FRAME 4
#define ZERO_TIMESTAMP_PERIOD 16384
#define MAX_CLIENT_READERS 64

typedef struct {
    UInt32 clientID;
    UInt32 initialized;
    UInt32 active;
    CKRemoteMicRingReader reader;
} ClientRingReader;

static pthread_mutex_t gStateMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t gClientMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t gIOMutex = PTHREAD_MUTEX_INITIALIZER;
static CKRemoteMicRingReader gRingReader = CK_REMOTE_MIC_RING_READER_INITIALIZER;
static ClientRingReader gClientReaders[MAX_CLIENT_READERS];
static UInt32 gRefCount = 0;
static UInt64 gIOCount = 0;
static UInt64 gTimestampCount = 0;
static UInt64 gAnchorHostTime = 0;
static Float64 gHostTicksPerFrame = 0;
static UInt32 gBoxAcquired = 1;
static AudioServerPlugInHostRef gHost = NULL;

static HRESULT QueryInterface(void *driver, REFIID uuid, LPVOID *outInterface);
static ULONG AddRef(void *driver);
static ULONG Release(void *driver);
static OSStatus Initialize(AudioServerPlugInDriverRef driver, AudioServerPlugInHostRef host);
static OSStatus UnsupportedCreate(AudioServerPlugInDriverRef driver, CFDictionaryRef desc, const AudioServerPlugInClientInfo *client, AudioObjectID *outID);
static OSStatus UnsupportedDestroy(AudioServerPlugInDriverRef driver, AudioObjectID id);
static OSStatus AddDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID id, const AudioServerPlugInClientInfo *client);
static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID id, const AudioServerPlugInClientInfo *client);
static OSStatus ConfigChange(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt64 action, void *info);
static OSStatus AbortConfigChange(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt64 action, void *info);
static Boolean HasProperty(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *address);
static OSStatus IsSettable(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *address, Boolean *outSettable);
static OSStatus GetDataSize(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *address, UInt32 qSize, const void *qData, UInt32 *outSize);
static OSStatus GetData(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *address, UInt32 qSize, const void *qData, UInt32 dataSize, UInt32 *outSize, void *outData);
static OSStatus SetData(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *address, UInt32 qSize, const void *qData, UInt32 dataSize, const void *data);
static OSStatus StartIO(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 clientID);
static OSStatus StopIO(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 clientID);
static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 clientID, Float64 *sampleTime, UInt64 *hostTime, UInt64 *seed);
static OSStatus WillDoIO(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 clientID, UInt32 operationID, Boolean *willDo, Boolean *willDoInPlace);
static OSStatus BeginIO(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 clientID, UInt32 op, UInt32 frames, const AudioServerPlugInIOCycleInfo *info);
static OSStatus DoIO(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, AudioObjectID streamID, UInt32 clientID, UInt32 op, UInt32 frames, const AudioServerPlugInIOCycleInfo *info, void *mainBuffer, void *secondaryBuffer);
static OSStatus EndIO(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 clientID, UInt32 op, UInt32 frames, const AudioServerPlugInIOCycleInfo *info);

static AudioServerPlugInDriverInterface gInterface = {
    NULL, QueryInterface, AddRef, Release, Initialize, UnsupportedCreate, UnsupportedDestroy,
    AddDeviceClient, RemoveDeviceClient, ConfigChange, AbortConfigChange, HasProperty,
    IsSettable, GetDataSize, GetData, SetData, StartIO, StopIO, GetZeroTimeStamp,
    WillDoIO, BeginIO, DoIO, EndIO
};
static AudioServerPlugInDriverInterface *gInterfacePtr = &gInterface;
static AudioServerPlugInDriverRef gDriverRef = &gInterfacePtr;

static CKRemoteMicRingReader *clientRingReaderForID(UInt32 clientID) {
    CKRemoteMicRingReader *reader = NULL;
    pthread_mutex_lock(&gClientMutex);
    for (UInt32 index = 0; index < MAX_CLIENT_READERS; ++index) {
        if (gClientReaders[index].active && gClientReaders[index].clientID == clientID) {
            reader = &gClientReaders[index].reader;
            break;
        }
    }
    if (reader == NULL) {
        for (UInt32 index = 0; index < MAX_CLIENT_READERS; ++index) {
            if (!gClientReaders[index].active) {
                if (!gClientReaders[index].initialized) {
                    CKRemoteMicRingReaderInit(&gClientReaders[index].reader);
                    gClientReaders[index].initialized = 1;
                } else {
                    CKRemoteMicRingReaderClose(&gClientReaders[index].reader);
                }
                gClientReaders[index].clientID = clientID;
                gClientReaders[index].active = 1;
                reader = &gClientReaders[index].reader;
                break;
            }
        }
    }
    pthread_mutex_unlock(&gClientMutex);
    return reader != NULL ? reader : &gRingReader;
}

static void removeClientRingReader(UInt32 clientID) {
    pthread_mutex_lock(&gClientMutex);
    for (UInt32 index = 0; index < MAX_CLIENT_READERS; ++index) {
        if (gClientReaders[index].active && gClientReaders[index].clientID == clientID) {
            gClientReaders[index].active = 0;
            CKRemoteMicRingReaderClose(&gClientReaders[index].reader);
            break;
        }
    }
    pthread_mutex_unlock(&gClientMutex);
}

__attribute__((visibility("default")))
void *ControllerKeysRemoteMic_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID) {
    (void)allocator;
    return CFEqual(requestedTypeUUID, kAudioServerPlugInTypeUUID) ? gDriverRef : NULL;
}

static int validDriver(AudioServerPlugInDriverRef driver) {
    return driver == gDriverRef;
}

static OSStatus copyOut(UInt32 dataSize, UInt32 *outSize, void *outData, const void *source, UInt32 size) {
    if (outSize == NULL || outData == NULL) return kAudioHardwareIllegalOperationError;
    if (dataSize < size) return kAudioHardwareBadPropertySizeError;
    if (size > 0) memcpy(outData, source, size);
    *outSize = size;
    return 0;
}

static AudioStreamBasicDescription streamFormat(void) {
    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = SAMPLE_RATE;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = BYTES_PER_FRAME;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = BYTES_PER_FRAME;
    format.mChannelsPerFrame = CHANNELS;
    format.mBitsPerChannel = 32;
    return format;
}


static void updateClock(void) {
    struct mach_timebase_info timebase;
    mach_timebase_info(&timebase);
    gHostTicksPerFrame = ((Float64)timebase.denom / (Float64)timebase.numer) * 1000000000.0 / SAMPLE_RATE;
}

static HRESULT QueryInterface(void *driver, REFIID uuid, LPVOID *outInterface) {
    if (driver != gDriverRef || outInterface == NULL) return kAudioHardwareBadObjectError;
    CFUUIDRef requested = CFUUIDCreateFromUUIDBytes(NULL, uuid);
    if (requested == NULL) return kAudioHardwareIllegalOperationError;
    if (CFEqual(requested, IUnknownUUID) || CFEqual(requested, kAudioServerPlugInDriverInterfaceUUID)) {
        AddRef(driver);
        *outInterface = gDriverRef;
        CFRelease(requested);
        return 0;
    }
    CFRelease(requested);
    return E_NOINTERFACE;
}

static ULONG AddRef(void *driver) {
    if (driver != gDriverRef) return 0;
    pthread_mutex_lock(&gStateMutex);
    if (gRefCount < UINT32_MAX) ++gRefCount;
    UInt32 answer = gRefCount;
    pthread_mutex_unlock(&gStateMutex);
    return answer;
}

static ULONG Release(void *driver) {
    if (driver != gDriverRef) return 0;
    pthread_mutex_lock(&gStateMutex);
    if (gRefCount > 0) --gRefCount;
    UInt32 answer = gRefCount;
    pthread_mutex_unlock(&gStateMutex);
    return answer;
}

static OSStatus Initialize(AudioServerPlugInDriverRef driver, AudioServerPlugInHostRef host) {
    if (!validDriver(driver)) return kAudioHardwareBadObjectError;
    gHost = host;
    updateClock();
    return 0;
}

static OSStatus UnsupportedCreate(AudioServerPlugInDriverRef driver, CFDictionaryRef desc, const AudioServerPlugInClientInfo *client, AudioObjectID *outID) {
    (void)desc; (void)client; (void)outID;
    return validDriver(driver) ? kAudioHardwareUnsupportedOperationError : kAudioHardwareBadObjectError;
}

static OSStatus UnsupportedDestroy(AudioServerPlugInDriverRef driver, AudioObjectID id) {
    (void)id;
    return validDriver(driver) ? kAudioHardwareUnsupportedOperationError : kAudioHardwareBadObjectError;
}

static OSStatus AddDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID id, const AudioServerPlugInClientInfo *client) {
    if (!validDriver(driver) || id != kObjectDevice) return kAudioHardwareBadObjectError;
    if (client != NULL) (void)clientRingReaderForID(client->mClientID);
    return 0;
}

static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID id, const AudioServerPlugInClientInfo *client) {
    if (!validDriver(driver) || id != kObjectDevice) return kAudioHardwareBadObjectError;
    if (client != NULL) removeClientRingReader(client->mClientID);
    return 0;
}

static OSStatus ConfigChange(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt64 action, void *info) {
    (void)action; (void)info;
    return validDriver(driver) && id == kObjectDevice ? 0 : kAudioHardwareBadObjectError;
}

static OSStatus AbortConfigChange(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt64 action, void *info) {
    (void)action; (void)info;
    return validDriver(driver) && id == kObjectDevice ? 0 : kAudioHardwareBadObjectError;
}

static Boolean HasProperty(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *a) {
    (void)pid;
    if (!validDriver(driver) || a == NULL) return false;
    switch (id) {
    case kObjectPlugIn:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
        case kAudioPlugInPropertyTranslateUIDToDevice:
        case kAudioPlugInPropertyBoxList:
        case kAudioPlugInPropertyTranslateUIDToBox:
        case kAudioPlugInPropertyResourceBundle:
            return true;
        }
        break;
    case kObjectBox:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioBoxPropertyBoxUID:
        case kAudioBoxPropertyTransportType:
        case kAudioBoxPropertyHasAudio:
        case kAudioBoxPropertyHasVideo:
        case kAudioBoxPropertyHasMIDI:
        case kAudioBoxPropertyIsProtected:
        case kAudioBoxPropertyAcquired:
        case kAudioBoxPropertyAcquisitionFailed:
        case kAudioBoxPropertyDeviceList:
        case kAudioBoxPropertyClockDeviceList:
            return a->mScope == kAudioObjectPropertyScopeGlobal;
        }
        break;
    case kObjectDevice:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyStreams:
        case kAudioObjectPropertyControlList:
        case kAudioDevicePropertyPreferredChannelsForStereo:
        case kAudioDevicePropertyPreferredChannelLayout:
        case kAudioDevicePropertyZeroTimeStampPeriod:
            return true;
        }
        break;
    case kObjectStreamInput:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioObjectPropertyName:
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            return true;
        }
        break;
    }
    return false;
}

static OSStatus IsSettable(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *a, Boolean *outSettable) {
    if (outSettable == NULL) return kAudioHardwareIllegalOperationError;
    if (!HasProperty(driver, id, pid, a)) return kAudioHardwareUnknownPropertyError;
    *outSettable = false;
    if (id == kObjectBox && a->mSelector == kAudioBoxPropertyAcquired) *outSettable = true;
    return 0;
}

static OSStatus GetDataSize(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *a, UInt32 qSize, const void *qData, UInt32 *outSize) {
    (void)qSize; (void)qData;
    if (outSize == NULL) return kAudioHardwareIllegalOperationError;
    if (!HasProperty(driver, id, pid, a)) return kAudioHardwareUnknownPropertyError;
    switch (a->mSelector) {
    case kAudioObjectPropertyBaseClass:
    case kAudioObjectPropertyClass:
        *outSize = sizeof(AudioClassID); return 0;
    case kAudioObjectPropertyOwner:
    case kAudioPlugInPropertyTranslateUIDToDevice:
    case kAudioPlugInPropertyTranslateUIDToBox:
        *outSize = sizeof(AudioObjectID); return 0;
    case kAudioObjectPropertyName:
    case kAudioObjectPropertyManufacturer:
    case kAudioDevicePropertyDeviceUID:
    case kAudioDevicePropertyModelUID:
    case kAudioBoxPropertyBoxUID:
    case kAudioPlugInPropertyResourceBundle:
        *outSize = sizeof(CFStringRef); return 0;
    case kAudioObjectPropertyOwnedObjects:
        if (id == kObjectPlugIn) {
            *outSize = 2 * sizeof(AudioObjectID); return 0;
        }
        if (id == kObjectDevice) {
            *outSize = (a->mScope == kAudioObjectPropertyScopeOutput) ? 0 : sizeof(AudioObjectID); return 0;
        }
        if (id == kObjectBox) {
            *outSize = sizeof(AudioObjectID); return 0;
        }
        *outSize = 0; return 0;
    case kAudioPlugInPropertyDeviceList:
    case kAudioPlugInPropertyBoxList:
    case kAudioBoxPropertyDeviceList:
    case kAudioDevicePropertyRelatedDevices:
    case kAudioDevicePropertyStreams:
        *outSize = (a->mScope == kAudioObjectPropertyScopeOutput) ? 0 : sizeof(AudioObjectID); return 0;
    case kAudioBoxPropertyClockDeviceList:
    case kAudioObjectPropertyControlList:
        *outSize = 0; return 0;
    case kAudioDevicePropertyAvailableNominalSampleRates:
        *outSize = sizeof(AudioValueRange); return 0;
    case kAudioDevicePropertyPreferredChannelsForStereo:
        *outSize = 2 * sizeof(UInt32); return 0;
    case kAudioDevicePropertyPreferredChannelLayout:
        *outSize = (UInt32)offsetof(AudioChannelLayout, mChannelDescriptions); return 0;
    case kAudioStreamPropertyVirtualFormat:
    case kAudioStreamPropertyPhysicalFormat:
        *outSize = sizeof(AudioStreamBasicDescription); return 0;
    case kAudioStreamPropertyAvailableVirtualFormats:
    case kAudioStreamPropertyAvailablePhysicalFormats:
        *outSize = sizeof(AudioStreamRangedDescription); return 0;
    default:
        *outSize = sizeof(UInt32); return 0;
    }
}

static OSStatus copyIDList(UInt32 dataSize, UInt32 *outSize, void *outData, AudioObjectID value, UInt32 count) {
    UInt32 requested = dataSize / sizeof(AudioObjectID);
    UInt32 returned = requested < count ? requested : count;
    if (returned > 0) ((AudioObjectID *)outData)[0] = value;
    *outSize = returned * sizeof(AudioObjectID);
    return 0;
}

static OSStatus copyIDArray(UInt32 dataSize, UInt32 *outSize, void *outData, const AudioObjectID *values, UInt32 count) {
    UInt32 requested = dataSize / sizeof(AudioObjectID);
    UInt32 returned = requested < count ? requested : count;
    if (returned > 0) memcpy(outData, values, returned * sizeof(AudioObjectID));
    *outSize = returned * sizeof(AudioObjectID);
    return 0;
}

static OSStatus GetData(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *a, UInt32 qSize, const void *qData, UInt32 dataSize, UInt32 *outSize, void *outData) {
    if (!HasProperty(driver, id, pid, a)) return kAudioHardwareUnknownPropertyError;
    AudioClassID classID;
    AudioObjectID objectID;
    UInt32 value;
    CFStringRef stringValue;
    AudioObjectID objectIDs[2];
    switch (id) {
    case kObjectPlugIn:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: classID = kAudioObjectClassID; return copyOut(dataSize, outSize, outData, &classID, sizeof(classID));
        case kAudioObjectPropertyClass: classID = kAudioPlugInClassID; return copyOut(dataSize, outSize, outData, &classID, sizeof(classID));
        case kAudioObjectPropertyOwner: objectID = kAudioObjectUnknown; return copyOut(dataSize, outSize, outData, &objectID, sizeof(objectID));
        case kAudioObjectPropertyName: stringValue = CFSTR("ControllerKeys Remote Mic Plug-In"); return copyOut(dataSize, outSize, outData, &stringValue, sizeof(stringValue));
        case kAudioObjectPropertyManufacturer: stringValue = CFSTR("Kevin Tang"); return copyOut(dataSize, outSize, outData, &stringValue, sizeof(stringValue));
        case kAudioObjectPropertyOwnedObjects:
            objectIDs[0] = kObjectBox; objectIDs[1] = kObjectDevice;
            return copyIDArray(dataSize, outSize, outData, objectIDs, 2);
        case kAudioPlugInPropertyDeviceList: return copyIDList(dataSize, outSize, outData, kObjectDevice, 1);
        case kAudioPlugInPropertyBoxList: return copyIDList(dataSize, outSize, outData, kObjectBox, 1);
        case kAudioPlugInPropertyTranslateUIDToDevice:
            if (qSize == sizeof(CFStringRef) && qData && CFStringCompare(*(CFStringRef *)qData, CFSTR(DEVICE_UID), 0) == kCFCompareEqualTo) objectID = kObjectDevice;
            else objectID = kAudioObjectUnknown;
            return copyOut(dataSize, outSize, outData, &objectID, sizeof(objectID));
        case kAudioPlugInPropertyTranslateUIDToBox:
            if (qSize == sizeof(CFStringRef) && qData && CFStringCompare(*(CFStringRef *)qData, CFSTR(BOX_UID), 0) == kCFCompareEqualTo) objectID = kObjectBox;
            else objectID = kAudioObjectUnknown;
            return copyOut(dataSize, outSize, outData, &objectID, sizeof(objectID));
        case kAudioPlugInPropertyResourceBundle: stringValue = CFSTR(""); return copyOut(dataSize, outSize, outData, &stringValue, sizeof(stringValue));
        }
        break;
    case kObjectBox:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: classID = kAudioObjectClassID; return copyOut(dataSize, outSize, outData, &classID, sizeof(classID));
        case kAudioObjectPropertyClass: classID = kAudioBoxClassID; return copyOut(dataSize, outSize, outData, &classID, sizeof(classID));
        case kAudioObjectPropertyOwner: objectID = kObjectPlugIn; return copyOut(dataSize, outSize, outData, &objectID, sizeof(objectID));
        case kAudioObjectPropertyName: stringValue = CFSTR("ControllerKeys Remote Mic Box"); return copyOut(dataSize, outSize, outData, &stringValue, sizeof(stringValue));
        case kAudioObjectPropertyManufacturer: stringValue = CFSTR("Kevin Tang"); return copyOut(dataSize, outSize, outData, &stringValue, sizeof(stringValue));
        case kAudioObjectPropertyOwnedObjects:
        case kAudioBoxPropertyDeviceList: return copyIDList(dataSize, outSize, outData, kObjectDevice, gBoxAcquired ? 1 : 0);
        case kAudioBoxPropertyClockDeviceList: *outSize = 0; return 0;
        case kAudioBoxPropertyBoxUID: stringValue = CFSTR(BOX_UID); return copyOut(dataSize, outSize, outData, &stringValue, sizeof(stringValue));
        case kAudioBoxPropertyTransportType: value = kAudioDeviceTransportTypeVirtual; return copyOut(dataSize, outSize, outData, &value, sizeof(value));
        case kAudioBoxPropertyHasAudio:
        case kAudioBoxPropertyAcquired: value = gBoxAcquired ? 1 : 0; return copyOut(dataSize, outSize, outData, &value, sizeof(value));
        case kAudioBoxPropertyHasVideo:
        case kAudioBoxPropertyHasMIDI:
        case kAudioBoxPropertyIsProtected:
        case kAudioBoxPropertyAcquisitionFailed: value = 0; return copyOut(dataSize, outSize, outData, &value, sizeof(value));
        }
        break;
    case kObjectDevice:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: classID = kAudioObjectClassID; return copyOut(dataSize, outSize, outData, &classID, sizeof(classID));
        case kAudioObjectPropertyClass: classID = kAudioDeviceClassID; return copyOut(dataSize, outSize, outData, &classID, sizeof(classID));
        case kAudioObjectPropertyOwner: objectID = kObjectPlugIn; return copyOut(dataSize, outSize, outData, &objectID, sizeof(objectID));
        case kAudioObjectPropertyName: stringValue = CFSTR("ControllerKeys Remote Mic"); return copyOut(dataSize, outSize, outData, &stringValue, sizeof(stringValue));
        case kAudioObjectPropertyManufacturer: stringValue = CFSTR("Kevin Tang"); return copyOut(dataSize, outSize, outData, &stringValue, sizeof(stringValue));
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyStreams:
            if (a->mScope == kAudioObjectPropertyScopeOutput) {
                *outSize = 0;
                return 0;
            }
            return copyIDList(dataSize, outSize, outData, kObjectStreamInput, 1);
        case kAudioDevicePropertyRelatedDevices: return copyIDList(dataSize, outSize, outData, kObjectDevice, 1);
        case kAudioObjectPropertyControlList: *outSize = 0; return 0;
        case kAudioDevicePropertyDeviceUID: stringValue = CFSTR(DEVICE_UID); return copyOut(dataSize, outSize, outData, &stringValue, sizeof(stringValue));
        case kAudioDevicePropertyModelUID: stringValue = CFSTR(MODEL_UID); return copyOut(dataSize, outSize, outData, &stringValue, sizeof(stringValue));
        case kAudioDevicePropertyTransportType: value = kAudioDeviceTransportTypeVirtual; return copyOut(dataSize, outSize, outData, &value, sizeof(value));
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: value = 0; return copyOut(dataSize, outSize, outData, &value, sizeof(value));
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice: value = 1; return copyOut(dataSize, outSize, outData, &value, sizeof(value));
        case kAudioDevicePropertyDeviceIsRunning:
            pthread_mutex_lock(&gStateMutex); value = gIOCount > 0 ? 1 : 0; pthread_mutex_unlock(&gStateMutex);
            return copyOut(dataSize, outSize, outData, &value, sizeof(value));
        case kAudioDevicePropertyNominalSampleRate: { Float64 rate = SAMPLE_RATE; return copyOut(dataSize, outSize, outData, &rate, sizeof(rate)); }
        case kAudioDevicePropertyAvailableNominalSampleRates: { AudioValueRange range = { SAMPLE_RATE, SAMPLE_RATE }; return copyOut(dataSize, outSize, outData, &range, sizeof(range)); }
        case kAudioDevicePropertyPreferredChannelsForStereo: { UInt32 channels[2] = { 1, 1 }; return copyOut(dataSize, outSize, outData, channels, sizeof(channels)); }
        case kAudioDevicePropertyPreferredChannelLayout: {
            AudioChannelLayout layout;
            memset(&layout, 0, sizeof(layout));
            layout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
            return copyOut(dataSize, outSize, outData, &layout, (UInt32)offsetof(AudioChannelLayout, mChannelDescriptions));
        }
        case kAudioDevicePropertyZeroTimeStampPeriod: value = ZERO_TIMESTAMP_PERIOD; return copyOut(dataSize, outSize, outData, &value, sizeof(value));
        }
        break;
    case kObjectStreamInput:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: classID = kAudioObjectClassID; return copyOut(dataSize, outSize, outData, &classID, sizeof(classID));
        case kAudioObjectPropertyClass: classID = kAudioStreamClassID; return copyOut(dataSize, outSize, outData, &classID, sizeof(classID));
        case kAudioObjectPropertyOwner: objectID = kObjectDevice; return copyOut(dataSize, outSize, outData, &objectID, sizeof(objectID));
        case kAudioObjectPropertyOwnedObjects: *outSize = 0; return 0;
        case kAudioObjectPropertyName: stringValue = CFSTR("Remote Mic Input"); return copyOut(dataSize, outSize, outData, &stringValue, sizeof(stringValue));
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection: value = 1; return copyOut(dataSize, outSize, outData, &value, sizeof(value));
        case kAudioStreamPropertyTerminalType: value = kAudioStreamTerminalTypeMicrophone; return copyOut(dataSize, outSize, outData, &value, sizeof(value));
        case kAudioStreamPropertyStartingChannel: value = 1; return copyOut(dataSize, outSize, outData, &value, sizeof(value));
        case kAudioStreamPropertyLatency: value = 0; return copyOut(dataSize, outSize, outData, &value, sizeof(value));
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: { AudioStreamBasicDescription format = streamFormat(); return copyOut(dataSize, outSize, outData, &format, sizeof(format)); }
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats: {
            AudioStreamRangedDescription desc;
            memset(&desc, 0, sizeof(desc));
            desc.mFormat = streamFormat();
            desc.mSampleRateRange.mMinimum = SAMPLE_RATE;
            desc.mSampleRateRange.mMaximum = SAMPLE_RATE;
            return copyOut(dataSize, outSize, outData, &desc, sizeof(desc));
        }
        }
        break;
    }
    return kAudioHardwareUnknownPropertyError;
}

static OSStatus SetData(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *address, UInt32 qSize, const void *qData, UInt32 dataSize, const void *data) {
    (void)pid; (void)qSize; (void)qData;
    if (!validDriver(driver)) return kAudioHardwareBadObjectError;
    if (id == kObjectBox && address && address->mSelector == kAudioBoxPropertyAcquired) {
        if (dataSize != sizeof(UInt32) || data == NULL) return kAudioHardwareBadPropertySizeError;
        pthread_mutex_lock(&gStateMutex);
        gBoxAcquired = (*(const UInt32 *)data) ? 1 : 0;
        pthread_mutex_unlock(&gStateMutex);
        return 0;
    }
    return (id == kObjectPlugIn || id == kObjectDevice || id == kObjectStreamInput || id == kObjectBox) ? kAudioHardwareUnsupportedOperationError : kAudioHardwareBadObjectError;
}

static OSStatus StartIO(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 clientID) {
    if (!validDriver(driver) || id != kObjectDevice) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gStateMutex);
    if (gIOCount++ == 0) {
        gTimestampCount = 0;
        gAnchorHostTime = mach_absolute_time();
    }
    pthread_mutex_unlock(&gStateMutex);
    CKRemoteMicRingOpenIfNeeded(clientRingReaderForID(clientID));
    return 0;
}

static OSStatus StopIO(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 clientID) {
    (void)clientID;
    if (!validDriver(driver) || id != kObjectDevice) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gStateMutex);
    if (gIOCount > 0) --gIOCount;
    pthread_mutex_unlock(&gStateMutex);
    return 0;
}

static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 clientID, Float64 *sampleTime, UInt64 *hostTime, UInt64 *seed) {
    (void)clientID;
    if (!validDriver(driver) || id != kObjectDevice) return kAudioHardwareBadObjectError;
    if (sampleTime == NULL || hostTime == NULL || seed == NULL) return kAudioHardwareIllegalOperationError;
    pthread_mutex_lock(&gIOMutex);
    UInt64 now = mach_absolute_time();
    Float64 periodTicks = gHostTicksPerFrame * ZERO_TIMESTAMP_PERIOD;
    if (gAnchorHostTime == 0 || periodTicks <= 0) {
        updateClock();
        gAnchorHostTime = now;
        gTimestampCount = 0;
        periodTicks = gHostTicksPerFrame * ZERO_TIMESTAMP_PERIOD;
    }
    if (periodTicks > 0 && now > gAnchorHostTime) {
        UInt64 elapsed = now - gAnchorHostTime;
        UInt64 currentPeriod = (UInt64)((Float64)elapsed / periodTicks);
        if (currentPeriod > gTimestampCount) gTimestampCount = currentPeriod;
    }
    *sampleTime = gTimestampCount * ZERO_TIMESTAMP_PERIOD;
    *hostTime = gAnchorHostTime + (UInt64)(gTimestampCount * periodTicks);
    *seed = 1;
    pthread_mutex_unlock(&gIOMutex);
    return 0;
}

static OSStatus WillDoIO(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 clientID, UInt32 operationID, Boolean *willDo, Boolean *willDoInPlace) {
    (void)clientID;
    if (!validDriver(driver) || id != kObjectDevice) return kAudioHardwareBadObjectError;
    Boolean read = operationID == kAudioServerPlugInIOOperationReadInput;
    if (willDo) *willDo = read;
    if (willDoInPlace) *willDoInPlace = true;
    return 0;
}

static OSStatus BeginIO(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 clientID, UInt32 op, UInt32 frames, const AudioServerPlugInIOCycleInfo *info) {
    (void)clientID; (void)op; (void)frames; (void)info;
    return validDriver(driver) && id == kObjectDevice ? 0 : kAudioHardwareBadObjectError;
}

static OSStatus DoIO(AudioServerPlugInDriverRef driver, AudioObjectID deviceID, AudioObjectID streamID, UInt32 clientID, UInt32 op, UInt32 frames, const AudioServerPlugInIOCycleInfo *info, void *mainBuffer, void *secondaryBuffer) {
    (void)info; (void)secondaryBuffer;
    if (!validDriver(driver) || deviceID != kObjectDevice || streamID != kObjectStreamInput) return kAudioHardwareBadObjectError;
    if (op == kAudioServerPlugInIOOperationReadInput && mainBuffer != NULL) {
        CKRemoteMicRingCopyFloatFrames(clientRingReaderForID(clientID), (Float32 *)mainBuffer, frames);
    }
    return 0;
}

static OSStatus EndIO(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 clientID, UInt32 op, UInt32 frames, const AudioServerPlugInIOCycleInfo *info) {
    (void)clientID; (void)op; (void)frames; (void)info;
    return validDriver(driver) && id == kObjectDevice ? 0 : kAudioHardwareBadObjectError;
}
