#ifndef CONTROLLERKEYS_REMOTE_MIC_RING_READER_H
#define CONTROLLERKEYS_REMOTE_MIC_RING_READER_H

#include <CoreAudio/AudioHardwareBase.h>
#include <fcntl.h>
#include <pthread.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "ControllerKeysRemoteMicRing.h"

typedef struct {
    pthread_mutex_t mutex;
    CKRemoteMicRing *ring;
    UInt64 readFrame;
    UInt64 lastResetCounter;
    UInt32 retryCountdown;
} CKRemoteMicRingReader;

#define CK_REMOTE_MIC_RING_READER_INITIALIZER { PTHREAD_MUTEX_INITIALIZER, NULL, 0, 0, 0 }

static void CKRemoteMicRingReaderInit(CKRemoteMicRingReader *reader) {
    if (reader == NULL) return;
    memset(reader, 0, sizeof(*reader));
    pthread_mutex_init(&reader->mutex, NULL);
}

static void CKRemoteMicRingReaderClose(CKRemoteMicRingReader *reader) {
    if (reader == NULL) return;
    pthread_mutex_lock(&reader->mutex);
    if (reader->ring != NULL) {
        munmap(reader->ring, sizeof(CKRemoteMicRing));
        reader->ring = NULL;
    }
    reader->readFrame = 0;
    reader->lastResetCounter = 0;
    reader->retryCountdown = 0;
    pthread_mutex_unlock(&reader->mutex);
}

static int CKRemoteMicRingIsValid(CKRemoteMicRing *ring) {
    return ring != NULL &&
        ring->magic == CK_REMOTE_MIC_MAGIC &&
        ring->version == CK_REMOTE_MIC_VERSION &&
        ring->sampleRate == CK_REMOTE_MIC_SAMPLE_RATE &&
        ring->channels == CK_REMOTE_MIC_CHANNELS &&
        ring->capacityFrames == CK_REMOTE_MIC_CAPACITY_FRAMES &&
        ring->bytesPerFrame == CK_REMOTE_MIC_BYTES_PER_FRAME;
}

static CKRemoteMicRing *CKRemoteMicRingOpenIfNeeded(CKRemoteMicRingReader *reader) {
    pthread_mutex_lock(&reader->mutex);
    if (reader->ring != NULL && CKRemoteMicRingIsValid(reader->ring)) {
        pthread_mutex_unlock(&reader->mutex);
        return reader->ring;
    }
    if (reader->ring != NULL) {
        munmap(reader->ring, sizeof(CKRemoteMicRing));
        reader->ring = NULL;
    }
    int fd = open(CK_REMOTE_MIC_RING_PATH, O_RDONLY);
    if (fd < 0) {
        pthread_mutex_unlock(&reader->mutex);
        return NULL;
    }
    CKRemoteMicRing *ring = mmap(NULL, sizeof(CKRemoteMicRing), PROT_READ, MAP_SHARED, fd, 0);
    close(fd);
    if (ring == MAP_FAILED || !CKRemoteMicRingIsValid(ring)) {
        if (ring != MAP_FAILED) munmap(ring, sizeof(CKRemoteMicRing));
        pthread_mutex_unlock(&reader->mutex);
        return NULL;
    }
    reader->ring = ring;
    reader->readFrame = ring->writeFrame;
    reader->lastResetCounter = ring->resetCounter;
    pthread_mutex_unlock(&reader->mutex);
    return ring;
}

static void CKRemoteMicRingReaderFlush(CKRemoteMicRingReader *reader) {
    if (reader == NULL) return;
    CKRemoteMicRing *ring = CKRemoteMicRingOpenIfNeeded(reader);
    if (ring == NULL || !CKRemoteMicRingIsValid(ring)) return;
    reader->readFrame = ring->writeFrame;
    reader->lastResetCounter = ring->resetCounter;
}

static __attribute__((unused)) void CKRemoteMicRingCopyFrames(CKRemoteMicRingReader *reader, SInt16 *out, UInt32 frames) {
    CKRemoteMicRing *ring = reader->ring;
    if (ring == NULL || !CKRemoteMicRingIsValid(ring)) {
        if (reader->retryCountdown++ % 32 == 0) ring = CKRemoteMicRingOpenIfNeeded(reader);
    }
    if (ring == NULL) {
        memset(out, 0, frames * CK_REMOTE_MIC_BYTES_PER_FRAME);
        return;
    }

    UInt64 resetCounter = ring->resetCounter;
    UInt64 writeFrame = ring->writeFrame;
    if (resetCounter != reader->lastResetCounter || writeFrame < reader->readFrame) {
        reader->readFrame = writeFrame;
        reader->lastResetCounter = resetCounter;
    }
    if (writeFrame > reader->readFrame + CK_REMOTE_MIC_CAPACITY_FRAMES) {
        reader->readFrame = writeFrame - CK_REMOTE_MIC_CAPACITY_FRAMES;
    }

    UInt64 available = writeFrame > reader->readFrame ? writeFrame - reader->readFrame : 0;
    UInt32 toRead = available < frames ? (UInt32)available : frames;
    UInt32 copied = 0;
    while (copied < toRead) {
        UInt32 ringIndex = (UInt32)(reader->readFrame % CK_REMOTE_MIC_CAPACITY_FRAMES);
        UInt32 chunk = CK_REMOTE_MIC_CAPACITY_FRAMES - ringIndex;
        if (chunk > toRead - copied) chunk = toRead - copied;
        memcpy(out + copied, ring->samples + ringIndex, chunk * CK_REMOTE_MIC_BYTES_PER_FRAME);
        copied += chunk;
        reader->readFrame += chunk;
    }
    if (copied < frames) {
        memset(out + copied, 0, (frames - copied) * CK_REMOTE_MIC_BYTES_PER_FRAME);
    }
}

static void CKRemoteMicRingCopyFloatFrames(CKRemoteMicRingReader *reader, Float32 *out, UInt32 frames) {
    CKRemoteMicRing *ring = reader->ring;
    if (ring == NULL || !CKRemoteMicRingIsValid(ring)) {
        if (reader->retryCountdown++ % 32 == 0) ring = CKRemoteMicRingOpenIfNeeded(reader);
    }
    if (ring == NULL) {
        memset(out, 0, frames * sizeof(Float32));
        return;
    }

    UInt64 resetCounter = ring->resetCounter;
    UInt64 writeFrame = ring->writeFrame;
    if (resetCounter != reader->lastResetCounter || writeFrame < reader->readFrame) {
        reader->readFrame = writeFrame;
        reader->lastResetCounter = resetCounter;
    }
    if (writeFrame > reader->readFrame + CK_REMOTE_MIC_CAPACITY_FRAMES) {
        reader->readFrame = writeFrame - CK_REMOTE_MIC_CAPACITY_FRAMES;
    }

    UInt64 available = writeFrame > reader->readFrame ? writeFrame - reader->readFrame : 0;
    UInt32 toRead = available < frames ? (UInt32)available : frames;
    UInt32 copied = 0;
    while (copied < toRead) {
        UInt32 ringIndex = (UInt32)(reader->readFrame % CK_REMOTE_MIC_CAPACITY_FRAMES);
        UInt32 chunk = CK_REMOTE_MIC_CAPACITY_FRAMES - ringIndex;
        if (chunk > toRead - copied) chunk = toRead - copied;
        for (UInt32 index = 0; index < chunk; ++index) {
            out[copied + index] = (Float32)ring->samples[ringIndex + index] / 32768.0f;
        }
        copied += chunk;
        reader->readFrame += chunk;
    }
    if (copied < frames) {
        memset(out + copied, 0, (frames - copied) * sizeof(Float32));
    }
}

#endif
