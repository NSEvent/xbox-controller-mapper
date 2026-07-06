#!/usr/bin/env python3
"""Decode Oura BLE traffic from a PacketLogger capture (.pklg).

Given a capture of the OFFICIAL Oura app talking to the ring (captured on the
iPhone via Apple's Bluetooth logging profile → sysdiagnose → the .pklg inside),
this extracts every ATT Write (app → ring) and Notification (ring → app) and
decodes the payload against the known Oura command grammar. The point is to see
the exact enable sequence the official app uses for tap-to-tag (feature 0x07) —
the command rounds 1-3 of the in-app probe never found.

  python3 decode_pklg.py capture.pklg
  python3 decode_pklg.py capture.pklg --all      # every ATT op, not just Oura-looking

PacketLogger record: [len u32 BE][ts_sec u32 BE][ts_usec u32 BE][type u8][data]
  type 0x02 = ACL sent (host→controller = app→ring writes)
  type 0x03 = ACL received (controller→host = ring→app notifications)
ACL: [handle+flags u16 LE][acl_len u16 LE] then L2CAP [len u16 LE][cid u16 LE]
     then ATT [opcode u8][payload]. ATT CID = 0x0004.
"""
import argparse
import struct
import sys
from pathlib import Path

ATT_CID = 0x0004
ATT_WRITE_REQ = 0x12
ATT_WRITE_CMD = 0x52
ATT_HANDLE_VALUE_NOTIFY = 0x1B
ATT_HANDLE_VALUE_IND = 0x1D

OURA_AUTH = {0x2F: "control", 0x06: "realtime", 0x25: "key-install", 0x23: "read-ack", 0x27: "read-ack", 0x33: "accel-frame"}


def decode_oura_payload(data: bytes) -> str:
	"""Best-effort semantic decode of an Oura command/response payload."""
	if not data:
		return ""
	head = data[0]
	hexs = data.hex(" ")
	if head == 0x2F and len(data) >= 3:
		sub, feat = data[1], data[2]
		verb = {0x01: "nonce-req", 0x02: "enable?", 0x03: "config?", 0x10: "nonce-resp",
			0x11: "auth-submit"}.get(sub, f"sub{sub:#04x}")
		reg = {0x20: "enable", 0x22: "cfg-A", 0x26: "cfg-B", 0x28: "PUSH", 0x2b: "nonce",
			0x2c: "nonce", 0x2d: "submit", 0x2e: "status"}.get(feat, f"reg{feat:#04x}")
		rest = data[3:].hex(" ")
		return f"control 2F {verb} {reg} [{rest}]" if rest else f"control 2F {verb} {reg}"
	if head == 0x06 and len(data) >= 3:
		bitmask = data[2]
		bits = "+".join(n for b, n in ((0x20, "accel"), (0x01, "f01"), (0x02, "f02"),
			(0x04, "f04"), (0x08, "f08")) if bitmask & b) or "none"
		return f"realtime start bitmask={bitmask:#04x} ({bits})"
	if head in (0x23, 0x27) and len(data) >= 3:
		return f"read-ack feature={data[1]:#04x} state={data[2]:#04x}"
	if head == 0x07 and len(data) >= 3:
		return f"feature-07 announce {data[1]:#04x} state={data[2]:#04x}  <-- TAP-TO-TAG"
	if head == 0x33:
		return f"accelerometer frame ({len(data)}B)"
	return f"{OURA_AUTH.get(head, 'unknown')}: {hexs}"


def looks_like_oura(data: bytes) -> bool:
	return bool(data) and data[0] in (0x2F, 0x06, 0x25, 0x23, 0x27, 0x33, 0x07)


def parse_att(payload: bytes):
	"""Return (kind, handle, value) for a write/notify ATT PDU, else None."""
	if len(payload) < 4:
		return None
	acl_len = struct.unpack_from("<H", payload, 2)[0]
	l2 = payload[4:4 + acl_len]
	if len(l2) < 4:
		return None
	l2_len, cid = struct.unpack_from("<HH", l2, 0)
	if cid != ATT_CID:
		return None
	att = l2[4:4 + l2_len]
	if len(att) < 3:
		return None
	op = att[0]
	if op in (ATT_WRITE_REQ, ATT_WRITE_CMD):
		handle = struct.unpack_from("<H", att, 1)[0]
		return ("WRITE", handle, att[3:])
	if op in (ATT_HANDLE_VALUE_NOTIFY, ATT_HANDLE_VALUE_IND):
		handle = struct.unpack_from("<H", att, 1)[0]
		return ("NOTIFY", handle, att[3:])
	return None


def iter_records(blob: bytes):
	off = 0
	n = len(blob)
	while off + 4 <= n:
		length = struct.unpack_from(">I", blob, off)[0]
		if length < 9 or off + 4 + length > n:
			break
		rec = blob[off + 4: off + 4 + length]
		ts_sec, ts_usec = struct.unpack_from(">II", rec, 0)
		rtype = rec[8]
		data = rec[9:]
		yield ts_sec + ts_usec / 1e6, rtype, data
		off += 4 + length


def main():
	parser = argparse.ArgumentParser(description="Decode Oura BLE writes/notifications from a .pklg capture.")
	parser.add_argument("pklg", type=Path)
	parser.add_argument("--all", action="store_true", help="show all ATT writes/notifies, not just Oura-looking")
	args = parser.parse_args()

	blob = args.pklg.read_bytes()
	t0 = None
	shown = 0
	for ts, rtype, data in iter_records(blob):
		if rtype not in (0x02, 0x03):
			continue
		att = parse_att(data)
		if not att:
			continue
		kind, handle, value = att
		if not args.all and not looks_like_oura(value):
			continue
		if t0 is None:
			t0 = ts
		direction = "app→ring" if rtype == 0x02 else "ring→app"
		print(f"+{ts - t0:8.3f}s  {direction}  h{handle:#06x}  {kind:<6}  {decode_oura_payload(value)}")
		shown += 1

	if shown == 0:
		print("No ATT writes/notifications found. Was the Bluetooth logging profile active "
			"during capture, and did the OFFICIAL app connect the ring?", file=sys.stderr)
		sys.exit(2)
	print(f"\n{shown} Oura ATT PDUs decoded. Look for a 'PUSH' (2F .. 28 07) or a realtime "
		"bitmask with an unfamiliar bit right before tap events appear.", file=sys.stderr)


if __name__ == "__main__":
	main()
