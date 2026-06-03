#!/usr/bin/env python3

import mmap
import os
import struct


RING_PATH = "/tmp/controllerkeys-remote-mic.pcm"
MAGIC = 0x434B524D
VERSION = 1
SAMPLE_RATE = 48_000
CHANNELS = 1
BYTES_PER_FRAME = 2
CAPACITY_FRAMES = SAMPLE_RATE * 4
HEADER = struct.Struct("<6I2Q")
WRITE_OFFSET = 24
RESET_OFFSET = 32
SAMPLES_OFFSET = HEADER.size
SIZE = SAMPLES_OFFSET + CAPACITY_FRAMES * BYTES_PER_FRAME
ZERO_SAMPLES = b"\0" * (CAPACITY_FRAMES * BYTES_PER_FRAME)


class CoreAudioRingWriter:
    def __init__(self, error_type=RuntimeError):
        self.error_type = error_type
        fd = self._open_shared_memory()

        try:
            try:
                os.fchmod(fd, 0o666)
            except OSError:
                pass
            os.ftruncate(fd, SIZE)
            self.map = mmap.mmap(fd, SIZE, flags=mmap.MAP_SHARED, prot=mmap.PROT_READ | mmap.PROT_WRITE)
        finally:
            os.close(fd)

        reset_counter = 0
        if self.map[:4] == struct.pack("<I", MAGIC):
            reset_counter = struct.unpack_from("<Q", self.map, RESET_OFFSET)[0]
        self.write_frame = 0
        self.reset_counter = reset_counter + 1
        self.map[SAMPLES_OFFSET : SAMPLES_OFFSET + len(ZERO_SAMPLES)] = ZERO_SAMPLES
        HEADER.pack_into(
            self.map,
            0,
            MAGIC,
            VERSION,
            SAMPLE_RATE,
            CHANNELS,
            CAPACITY_FRAMES,
            BYTES_PER_FRAME,
            self.write_frame,
            self.reset_counter,
        )

    def reset(self):
        self.write_frame = 0
        self.map[SAMPLES_OFFSET : SAMPLES_OFFSET + len(ZERO_SAMPLES)] = ZERO_SAMPLES
        struct.pack_into("<Q", self.map, WRITE_OFFSET, self.write_frame)
        self.reset_counter += 1
        struct.pack_into("<Q", self.map, RESET_OFFSET, self.reset_counter)

    def write_pcm(self, pcm: bytes):
        if not pcm:
            return
        if len(pcm) % BYTES_PER_FRAME != 0:
            pcm = pcm[: len(pcm) - (len(pcm) % BYTES_PER_FRAME)]
        max_bytes = CAPACITY_FRAMES * BYTES_PER_FRAME
        if len(pcm) > max_bytes:
            pcm = pcm[-max_bytes:]

        frames = len(pcm) // BYTES_PER_FRAME
        start_frame = self.write_frame % CAPACITY_FRAMES
        start_byte = SAMPLES_OFFSET + start_frame * BYTES_PER_FRAME
        first_frames = min(frames, CAPACITY_FRAMES - start_frame)
        first_bytes = first_frames * BYTES_PER_FRAME
        self.map[start_byte : start_byte + first_bytes] = pcm[:first_bytes]
        remaining = len(pcm) - first_bytes
        if remaining > 0:
            self.map[SAMPLES_OFFSET : SAMPLES_OFFSET + remaining] = pcm[first_bytes:]

        self.write_frame += frames
        struct.pack_into("<Q", self.map, WRITE_OFFSET, self.write_frame)

    def close(self):
        if getattr(self, "map", None) is not None:
            self.map.close()
            self.map = None

    def _open_shared_memory(self):
        old_umask = os.umask(0)
        try:
            return os.open(RING_PATH, os.O_CREAT | os.O_RDWR, 0o666)
        except OSError as error:
            raise self.error_type(f"open ring failed: {error.strerror}") from error
        finally:
            os.umask(old_umask)
