#!/usr/bin/env python3

import argparse
import importlib.util
import os
from collections import OrderedDict
from pathlib import Path
import re
import select
import subprocess
import sys
import time


SCRIPT_DIR = Path(__file__).resolve().parent
PACKETLOGGER = "/Applications/PacketLogger.app/Contents/Resources/packetlogger"
WHISPER_BIN = Path("~/projects/oss/whisper.cpp/build/bin/whisper-cli").expanduser()
WHISPER_MODEL = Path("~/projects/oss/whisper.cpp/models/ggml-base.en.bin").expanduser()
L2CAP_ATT_CID = 0x0004
ATT_NOTIFY = 0x1B
ATT_INDICATE = 0x1D
SIRI_BUTTON_HANDLE = 0x003A
SIRI_BUTTON_MASK = 0x20
HEX_BYTE = re.compile(r"^[0-9A-Fa-f]{2}$")


class LiveError(Exception):
    pass


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Decode Apple TV / Siri Remote mic audio from PacketLogger raw stdout."
    )
    parser.add_argument(
        "--capture",
        action="store_true",
        help="Run sudo packetlogger convert --stdout --format ir and consume it live.",
    )
    parser.add_argument(
        "--seconds",
        type=float,
        default=None,
        help="Seconds to capture when --capture is used. Omit to stop with Ctrl-C.",
    )
    parser.add_argument(
        "-i",
        "--input",
        default="-",
        help="PacketLogger convert text file, or '-' for stdin. Ignored with --capture.",
    )
    parser.add_argument(
        "-o",
        "--output",
        default=str(Path("~/Downloads/siri-remote-live.wav").expanduser()),
        help="Output WAV path.",
    )
    parser.add_argument(
        "--transcribe",
        action="store_true",
        help="Run whisper.cpp after writing the WAV.",
    )
    parser.add_argument("--transcript", default=None, help="Transcript path. Default: output .txt")
    parser.add_argument("--packetlogger", default=PACKETLOGGER, help="PacketLogger CLI path.")
    parser.add_argument("--no-sudo", action="store_true", help="Do not prefix live capture with sudo.")
    parser.add_argument(
        "--enable-hid",
        action="store_true",
        help="Also run the IOHID probe to send the Siri Remote mic enable byte.",
    )
    parser.add_argument(
        "--stop-on-release",
        action="store_true",
        help="Stop live capture shortly after the Siri/mic button is released.",
    )
    parser.add_argument(
        "--release-grace",
        type=float,
        default=0.35,
        help="Extra seconds to read after Siri/mic release when --stop-on-release is used.",
    )
    parser.add_argument(
        "--hid-probe",
        default=str(SCRIPT_DIR / "apple-tv-remote-mic-probe.swift"),
        help="IOHID probe script used by --enable-hid.",
    )
    parser.add_argument("--whisper-bin", default=str(WHISPER_BIN), help="whisper.cpp CLI path.")
    parser.add_argument("--whisper-model", default=str(WHISPER_MODEL), help="whisper.cpp model path.")
    args = parser.parse_args()

    decoder = load_decoder()
    packet_parser = PacketLoggerRawParser(decoder)

    if args.capture:
        read_live_capture(args, packet_parser)
    else:
        read_input(args.input, packet_parser)

    packets = packet_parser.packets()
    if not packets:
        raise LiveError(
            "no mic packets found; hold the Siri/mic button while PacketLogger is capturing"
        )

    output = Path(args.output).expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)
    pcm = decoder.decode_opus_packets([packet["opus"] for packet in packets])
    decoder.write_wav(output, pcm)

    sequences = [packet["seq"] for packet in packets]
    gaps = decoder.count_sequence_gaps(sequences)
    duration = len(pcm) / 2 / decoder.SAMPLE_RATE
    print(f"rawRows={packet_parser.raw_rows} skippedRows={packet_parser.skipped_rows}")
    print(
        f"buttonEvents={packet_parser.button_events} "
        f"siriPressed={str(packet_parser.siri_pressed).lower()} "
        f"siriReleased={str(packet_parser.siri_released).lower()} "
        f"releaseAfterMic={str(packet_parser.siri_released_after_mic).lower()}"
    )
    print(
        f"packets={len(packets)} firstSeq={sequences[0]} "
        f"lastSeq={sequences[-1]} sequenceGaps={gaps}"
    )
    print(f"wav={output} duration={duration:.2f}s samples={len(pcm) // 2}")

    if args.transcribe:
        transcribe(output, args)

    return 0


class PacketLoggerRawParser:
    def __init__(self, decoder):
        self.decoder = decoder
        self.raw_rows = 0
        self.skipped_rows = 0
        self._packets_by_seq = OrderedDict()
        self._fallback_records = []
        self.button_events = 0
        self.siri_pressed = False
        self.siri_released = False
        self.siri_released_after_mic = False

    def add_line(self, line: str):
        raw = parse_hex_row(line)
        if raw is None:
            self.skipped_rows += 1
            return
        self.raw_rows += 1
        sequence = self.raw_rows

        packet = self._packet_from_converted_acl(raw, sequence)
        if packet is not None:
            self._packets_by_seq.setdefault(packet["seq"], packet)
            if self.siri_released:
                self.siri_released_after_mic = True
        self._scan_button_state(raw)

        if raw:
            hci_raw = raw if raw[0] == self.decoder.HCI_ACL else bytes([self.decoder.HCI_ACL]) + raw
            self._fallback_records.append({"sequence": sequence, "bytes": hci_raw})

    def packets(self):
        if self._packets_by_seq:
            return list(self._packets_by_seq.values())
        return self.decoder.extract_mic_packets(self._fallback_records)

    def _packet_from_converted_acl(self, raw: bytes, sequence: int):
        if raw and raw[0] == self.decoder.HCI_ACL:
            raw = raw[1:]
        if len(raw) < 11:
            return None

        l2cap_length = self.decoder.read_u16le(raw, 4)
        cid = self.decoder.read_u16le(raw, 6)
        if cid != L2CAP_ATT_CID or len(raw) < 8 + l2cap_length:
            return None

        att = raw[8 : 8 + l2cap_length]
        if len(att) < 3 or att[0] not in (ATT_NOTIFY, ATT_INDICATE):
            return None

        handle = self.decoder.read_u16le(att, 1)
        mic = self.decoder.parse_mic_payload(att[3:])
        if mic is None:
            return None

        seq, opus = mic
        return {"seq": seq, "handle": handle, "opus": opus, "record": sequence}

    def _scan_button_state(self, raw: bytes):
        att = self._att_from_converted_acl(raw)
        if att is None or len(att) < 5 or att[0] not in (ATT_NOTIFY, ATT_INDICATE):
            return

        handle = self.decoder.read_u16le(att, 1)
        value = att[3:]
        if handle != SIRI_BUTTON_HANDLE or len(value) < 2:
            return

        self._update_siri_state((value[0] & SIRI_BUTTON_MASK) != 0)

    def add_hid_probe_line(self, line: str):
        if "REMOTE reportID=0xFB" not in line or "bytes=" not in line:
            return

        raw = parse_hex_row(line.split("bytes=", 1)[1])
        if raw is None or len(raw) < 2 or raw[0] != 0xFB:
            return

        self._update_siri_state((raw[1] & SIRI_BUTTON_MASK) != 0)

    def _update_siri_state(self, is_pressed: bool):
        if is_pressed != self.siri_pressed:
            self.button_events += 1
        if is_pressed:
            self.siri_pressed = True
            self.siri_released = False
            return

        self.siri_released = True
        if self._packets_by_seq:
            self.siri_released_after_mic = True
        self.siri_pressed = False

    def _att_from_converted_acl(self, raw: bytes):
        if raw and raw[0] == self.decoder.HCI_ACL:
            raw = raw[1:]
        if len(raw) < 11:
            return None

        l2cap_length = self.decoder.read_u16le(raw, 4)
        cid = self.decoder.read_u16le(raw, 6)
        if cid != L2CAP_ATT_CID or len(raw) < 8 + l2cap_length:
            return None
        return raw[8 : 8 + l2cap_length]


def parse_hex_row(line: str):
    line = line.strip()
    if not line:
        return None

    # PacketLogger `--format ir` emits an ISO timestamp, at least two spaces,
    # then the raw HCI row. Splitting there avoids parsing date/time digits.
    candidates = []
    parts = re.split(r"\s{2,}", line, maxsplit=1)
    if len(parts) == 2:
        candidates.append(parts[1])
    candidates.append(line)

    for candidate in candidates:
        tokens = candidate.strip().split()
        if tokens and all(HEX_BYTE.match(token) for token in tokens):
            return bytes(int(token, 16) for token in tokens)

    tokens = line.split()
    for index in range(len(tokens)):
        suffix = tokens[index:]
        if suffix and all(HEX_BYTE.match(token) for token in suffix):
            return bytes(int(token, 16) for token in suffix)
    return None


def read_input(input_path: str, packet_parser: PacketLoggerRawParser):
    if input_path == "-":
        for line in sys.stdin:
            packet_parser.add_line(line)
        return

    with Path(input_path).expanduser().open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            packet_parser.add_line(line)


def read_live_capture(args, packet_parser: PacketLoggerRawParser):
    packetlogger = Path(args.packetlogger).expanduser()
    if not packetlogger.exists():
        raise LiveError(f"packetlogger CLI not found: {packetlogger}")

    command = [str(packetlogger), "convert", "--stdout", "--format", "ir"]
    if not args.no_sudo and os.geteuid() != 0:
        command.insert(0, "sudo")

    print("running: " + " ".join(command), file=sys.stderr)
    print("hold Siri/mic and speak; stop with Ctrl-C", file=sys.stderr)

    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=None,
        stdin=None,
        text=True,
        bufsize=1,
    )
    if process.stdout is None:
        raise LiveError("packetlogger stdout pipe was not created")

    enabler = None
    deadline = time.monotonic() + args.seconds if args.seconds else None
    release_deadline = None
    try:
        if args.enable_hid:
            time.sleep(0.5)
            enabler = start_hid_enabler(args)

        while True:
            if deadline is not None and time.monotonic() >= deadline:
                break
            if release_deadline is not None and time.monotonic() >= release_deadline:
                break

            timeout = 0.25
            next_deadline = deadline
            if release_deadline is not None:
                next_deadline = min(next_deadline, release_deadline) if next_deadline else release_deadline
            if next_deadline is not None:
                timeout = max(0.0, min(timeout, next_deadline - time.monotonic()))

            streams = [process.stdout]
            if enabler is not None and enabler.stdout is not None:
                streams.append(enabler.stdout)

            ready, _, _ = select.select(streams, [], [], timeout)
            if not ready:
                if process.poll() is not None:
                    break
                continue

            for stream in ready:
                line = stream.readline()
                if line == "":
                    if enabler is not None and stream is enabler.stdout:
                        enabler = None
                        continue
                    return

                if enabler is not None and stream is enabler.stdout:
                    sys.stderr.write(line)
                    packet_parser.add_hid_probe_line(line)
                else:
                    packet_parser.add_line(line)

            release_deadline = arm_release_deadline(args, packet_parser, release_deadline)
    except KeyboardInterrupt:
        print("stopping capture", file=sys.stderr)
    finally:
        if enabler is not None:
            stop_process(enabler, lambda line: handle_hid_probe_line(packet_parser, line))
        stop_process(process, packet_parser.add_line)


def arm_release_deadline(args, packet_parser: PacketLoggerRawParser, release_deadline):
    if not args.stop_on_release or not packet_parser.siri_released or release_deadline is not None:
        return release_deadline

    grace = max(0.0, args.release_grace)
    print(f"Siri release detected; stopping capture in {grace:.2f}s", file=sys.stderr)
    return time.monotonic() + grace


def handle_hid_probe_line(packet_parser: PacketLoggerRawParser, line: str):
    sys.stderr.write(line)
    packet_parser.add_hid_probe_line(line)


def start_hid_enabler(args):
    hid_probe = Path(args.hid_probe).expanduser()
    if not hid_probe.exists():
        raise LiveError(f"HID probe not found: {hid_probe}")

    seconds = args.seconds if args.seconds else 3600
    command = ["swift", str(hid_probe), "--seconds", str(seconds)]
    print("running HID enabler: " + " ".join(command), file=sys.stderr)
    return subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        stdin=None,
        text=True,
        bufsize=1,
    )


def stop_process(process: subprocess.Popen, line_handler=None):
    if process.poll() is None:
        process.terminate()

    try:
        output, _ = process.communicate(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()
        output, _ = process.communicate(timeout=2)

    if line_handler is not None and output:
        for line in output.splitlines(keepends=True):
            line_handler(line)


def transcribe(wav_path: Path, args):
    whisper_bin = Path(args.whisper_bin).expanduser()
    whisper_model = Path(args.whisper_model).expanduser()
    transcript = Path(args.transcript).expanduser() if args.transcript else wav_path.with_suffix(".txt")

    if not whisper_bin.exists():
        raise LiveError(f"whisper binary not found: {whisper_bin}")
    if not whisper_model.exists():
        raise LiveError(f"whisper model not found: {whisper_model}")

    command = [
        str(whisper_bin),
        "-m",
        str(whisper_model),
        "-f",
        str(wav_path),
        "-nt",
        "-np",
    ]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    transcript.write_text(result.stdout, encoding="utf-8")
    print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
    print(f"transcript={transcript}")
    if result.returncode != 0:
        raise LiveError(f"whisper failed with exit code {result.returncode}")


def load_decoder():
    path = SCRIPT_DIR / "apple-tv-remote-pklg-decode.py"
    spec = importlib.util.spec_from_file_location("apple_tv_remote_pklg_decode", path)
    if spec is None or spec.loader is None:
        raise LiveError(f"could not load decoder module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except LiveError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
