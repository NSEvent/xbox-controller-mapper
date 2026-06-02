#ifndef CONTROLLERKEYS_REMOTE_MIC_RING_H
#define CONTROLLERKEYS_REMOTE_MIC_RING_H

#include <stdint.h>

#define CK_REMOTE_MIC_RING_PATH "/tmp/controllerkeys-remote-mic.pcm"
#define CK_REMOTE_MIC_MAGIC 0x434B524D
#define CK_REMOTE_MIC_VERSION 1
#define CK_REMOTE_MIC_SAMPLE_RATE 48000
#define CK_REMOTE_MIC_CHANNELS 1
#define CK_REMOTE_MIC_BYTES_PER_FRAME 2
#define CK_REMOTE_MIC_CAPACITY_FRAMES (CK_REMOTE_MIC_SAMPLE_RATE * 4)

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t sampleRate;
    uint32_t channels;
    uint32_t capacityFrames;
    uint32_t bytesPerFrame;
    volatile uint64_t writeFrame;
    volatile uint64_t resetCounter;
    int16_t samples[CK_REMOTE_MIC_CAPACITY_FRAMES];
} CKRemoteMicRing;

#endif
