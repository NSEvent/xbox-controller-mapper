#!/usr/bin/env python3

import argparse
import ctypes
import ctypes.util
from pathlib import Path
import wave


HCI_ACL = 0x02
L2CAP_ATT_CID = 0x0004
ATT_NOTIFY = 0x1B
ATT_INDICATE = 0x1D
SAMPLE_RATE = 48_000
CHANNELS = 1
FRAME_SAMPLES = 960  # 20 ms at 48 kHz.


class DecodeError(Exception):
    pass


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Decode Apple TV / Siri Remote mic packets from PacketLogger .pklg to WAV."
    )
    parser.add_argument("capture", help="PacketLogger .pklg capture")
    parser.add_argument(
        "-o",
        "--output",
        default=None,
        help="Output WAV path. Default: capture basename + .siri-remote-mic.wav",
    )
    args = parser.parse_args()

    capture = Path(args.capture).expanduser()
    output = Path(args.output).expanduser() if args.output else capture.with_suffix(".siri-remote-mic.wav")

    data = capture.read_bytes()
    records = parse_packetlogger(data)
    packets = extract_mic_packets(records)
    if not packets:
        raise DecodeError("no mic packets found")

    pcm = decode_opus_packets([packet["opus"] for packet in packets])
    write_wav(output, pcm)

    sequences = [packet["seq"] for packet in packets]
    gaps = count_sequence_gaps(sequences)
    duration = len(pcm) / 2 / SAMPLE_RATE
    print(f"capture={capture}")
    print(f"packets={len(packets)} firstSeq={sequences[0]} lastSeq={sequences[-1]} sequenceGaps={gaps}")
    print(f"wav={output} duration={duration:.2f}s samples={len(pcm) // 2}")
    return 0


def parse_packetlogger(data: bytes):
    little = parse_packetlogger_endian(data, "little")
    big = parse_packetlogger_endian(data, "big")
    if len(little) > len(big):
        return little
    return big


def parse_packetlogger_endian(data: bytes, endian: str):
    offset = 0
    records = []
    sequence = 1
    while offset + 13 <= len(data):
        length = int.from_bytes(data[offset : offset + 4], endian)
        packet_type = data[offset + 12]
        if length < 9:
            break
        payload_length = length - 9
        payload_start = offset + 13
        next_offset = payload_start + payload_length
        if next_offset > len(data):
            break
        payload = data[payload_start:next_offset]
        offset = next_offset

        uart_type = packetlogger_uart_type(packet_type)
        if uart_type is not None:
            records.append(
                {
                    "sequence": sequence,
                    "packet_type": packet_type,
                    "direction": "rx" if packet_type == 0x03 else "tx",
                    "bytes": bytes([uart_type]) + payload,
                }
            )
        sequence += 1
    return records


def packetlogger_uart_type(packet_type: int):
    if packet_type == 0x00:
        return 0x01
    if packet_type == 0x01:
        return 0x04
    if packet_type in (0x02, 0x03):
        return HCI_ACL
    return None


def extract_mic_packets(records):
    pending_l2cap = {}
    packets = []

    for record in records:
        raw = record["bytes"]
        if len(raw) < 5 or raw[0] != HCI_ACL:
            continue
        handle_pb_bc = read_u16le(raw, 1)
        connection_handle = handle_pb_bc & 0x0FFF
        pb = (handle_pb_bc >> 12) & 0x03
        acl_length = read_u16le(raw, 3)
        if len(raw) < 5 + acl_length:
            continue
        acl_payload = raw[5 : 5 + acl_length]
        if not acl_payload:
            continue

        if pb == 0x01:
            pending = pending_l2cap.get(connection_handle)
            if pending is None:
                continue
            pending["payload"] += acl_payload
            if len(pending["payload"]) >= pending["expected_length"]:
                payload = pending["payload"][: pending["expected_length"]]
                cid = pending["cid"]
                pending_l2cap.pop(connection_handle, None)
                packets.extend(scan_l2cap_payload(cid, payload, record))
            continue

        if len(acl_payload) < 4:
            continue
        l2cap_length = read_u16le(acl_payload, 0)
        cid = read_u16le(acl_payload, 2)
        l2cap_payload = acl_payload[4:]
        if len(l2cap_payload) >= l2cap_length:
            packets.extend(scan_l2cap_payload(cid, l2cap_payload[:l2cap_length], record))
        else:
            pending_l2cap[connection_handle] = {
                "expected_length": l2cap_length,
                "cid": cid,
                "payload": l2cap_payload,
            }

    packets.sort(key=lambda packet: packet["seq"])
    return packets


def scan_l2cap_payload(cid: int, payload: bytes, record):
    if cid != L2CAP_ATT_CID or len(payload) < 4:
        return []
    opcode = payload[0]
    if opcode not in (ATT_NOTIFY, ATT_INDICATE):
        return []
    handle = read_u16le(payload, 1)
    value = payload[3:]
    mic = parse_mic_payload(value)
    if mic is None:
        return []
    seq, opus = mic
    return [{"seq": seq, "handle": handle, "opus": opus, "record": record["sequence"]}]


def parse_mic_payload(value: bytes):
    if len(value) == 100 and value[0] == 0xFA:
        value = value[1:]
    if len(value) != 99 or len(value) < 6:
        return None
    seq = read_u16le(value, 2)
    frame_len = value[4]
    if frame_len <= 0 or frame_len > 94 or 5 + frame_len > len(value):
        return None
    return seq, value[5 : 5 + frame_len]


def decode_opus_packets(frames):
    lib = load_opus()
    error = ctypes.c_int()
    decoder = lib.opus_decoder_create(SAMPLE_RATE, CHANNELS, ctypes.byref(error))
    if not decoder or error.value != 0:
        raise DecodeError(f"opus_decoder_create failed: {error.value}")

    output = bytearray()
    try:
        for frame in frames:
            frame_buffer = (ctypes.c_ubyte * len(frame)).from_buffer_copy(frame)
            pcm_buffer = (ctypes.c_int16 * (FRAME_SAMPLES * CHANNELS))()
            decoded = lib.opus_decode(
                decoder,
                frame_buffer,
                len(frame),
                pcm_buffer,
                FRAME_SAMPLES,
                0,
            )
            if decoded < 0:
                raise DecodeError(f"opus_decode failed: {decoded}")
            output.extend(ctypes.string_at(pcm_buffer, decoded * CHANNELS * 2))
    finally:
        lib.opus_decoder_destroy(decoder)
    return bytes(output)


def load_opus():
    candidates = [
        ctypes.util.find_library("opus"),
        "/opt/homebrew/lib/libopus.dylib",
        "/usr/local/lib/libopus.dylib",
    ]
    for candidate in candidates:
        if not candidate:
            continue
        try:
            lib = ctypes.CDLL(candidate)
            lib.opus_decoder_create.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
            lib.opus_decoder_create.restype = ctypes.c_void_p
            lib.opus_decode.argtypes = [
                ctypes.c_void_p,
                ctypes.POINTER(ctypes.c_ubyte),
                ctypes.c_int,
                ctypes.POINTER(ctypes.c_int16),
                ctypes.c_int,
                ctypes.c_int,
            ]
            lib.opus_decode.restype = ctypes.c_int
            lib.opus_decoder_destroy.argtypes = [ctypes.c_void_p]
            lib.opus_decoder_destroy.restype = None
            return lib
        except OSError:
            continue
    raise DecodeError("libopus not found; install with `brew install opus`")


def write_wav(path: Path, pcm: bytes):
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(CHANNELS)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(pcm)


def count_sequence_gaps(sequences):
    if len(sequences) < 2:
        return 0
    gaps = 0
    previous = sequences[0]
    for seq in sequences[1:]:
        expected = (previous + 1) & 0xFFFF
        if seq != expected:
            gaps += 1
        previous = seq
    return gaps


def read_u16le(data: bytes, offset: int) -> int:
    return data[offset] | (data[offset + 1] << 8)


if __name__ == "__main__":
    raise SystemExit(main())
