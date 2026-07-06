#!/usr/bin/env python3
"""Build a per-event training dataset from a labeled Oura gesture session.

Input: a capture dir produced by Tools/oura-calibration (gestures.html session
analyzed by analyze_gestures.py — needs gesture-dataset.ndjson and
motion-trace.ndjson).

Turns trial-level labels into event-level examples:
  - jerk-impulse peaks inside tap trials → "tap" (top-N by amplitude for an
    N-tap trial), clearly weaker leftovers → "noise" (ring-down ghosts),
    in-between leftovers discarded as ambiguous
  - the dominant px/py step inside a flick trial → "flick-up/down/left/right"
    (one event per trial; other peaks discarded)
  - every peak inside noise trials → "noise"
  - jerk peaks in the rest phases BETWEEN trials (from the full trace) →
    "noise" — hard negatives: hand repositioning right after gestures

Each event is a fixed 32×5 window ([x, y, z, px, py] resampled to 50 Hz over
peak-0.26s … peak+0.38s). Output: events.ndjson, one JSON object per event
with label, window, group (for grouped CV), and provenance.
"""
import argparse
import bisect
import json
import math
from collections import Counter
from pathlib import Path


WINDOW_PRE = 0.26
WINDOW_POST = 0.24
WINDOW_STEPS = 32
PEAK_THRESHOLD = 0.35
PEAK_MIN_SEPARATION = 0.18
TAP_MIN_SEPARATION = 0.25
GHOST_AMPLITUDE_RATIO = 0.6
MIN_WINDOW_COVERAGE = 0.6

EXPECTED_TAPS = {"single-tap": 1, "double-tap": 2, "triple-tap": 3, "five-tap": 5, "tap-hold": 1}


def dedup_stream(samples):
	"""samples: [t, ct, x, y, z, px, py] rows → (cts, rows) sorted by ct."""
	rows = sorted(samples, key=lambda s: s[1])
	return [r[1] for r in rows], rows


def jerk_peaks(cts, rows, threshold):
	"""Local maxima of |Δxyz| between consecutive samples (>1ms apart)."""
	series = []
	for a, b in zip(rows, rows[1:]):
		if b[1] - a[1] < 0.001:
			continue
		j = math.sqrt((b[2] - a[2]) ** 2 + (b[3] - a[3]) ** 2 + (b[4] - a[4]) ** 2)
		series.append((b[1], j))
	peaks = []
	for i in range(1, len(series) - 1):
		ct, j = series[i]
		if j >= threshold and j >= series[i - 1][1] and j >= series[i + 1][1]:
			peaks.append((ct, j))
	# enforce min separation, keeping the larger peak
	peaks.sort(key=lambda p: -p[1])
	kept = []
	for ct, j in peaks:
		if all(abs(ct - k[0]) >= PEAK_MIN_SEPARATION for k in kept):
			kept.append((ct, j))
	return sorted(kept)


def extract_window(cts, rows, center_ct):
	"""Resample [x,y,z,px,py] to WINDOW_STEPS uniform steps around center_ct.
	Linear interpolation on ct; edge replication outside coverage. Returns
	None when less than MIN_WINDOW_COVERAGE of the span has samples."""
	lo, hi = center_ct - WINDOW_PRE, center_ct + WINDOW_POST
	i0 = bisect.bisect_left(cts, lo)
	i1 = bisect.bisect_right(cts, hi)
	if i1 <= i0:
		return None
	covered = min(cts[i1 - 1], hi) - max(cts[i0], lo)
	if covered < MIN_WINDOW_COVERAGE * (hi - lo):
		return None

	window = []
	j = max(i0, 1)
	for step in range(WINDOW_STEPS):
		target = lo + (hi - lo) * step / (WINDOW_STEPS - 1)
		while j < len(cts) - 1 and cts[j] < target:
			j += 1
		a, b = rows[j - 1], rows[j]
		span = b[1] - a[1]
		frac = 0.0 if span <= 0 else min(1.0, max(0.0, (target - a[1]) / span))
		window.append([round(a[k] + (b[k] - a[k]) * frac, 4) for k in (2, 3, 4, 5, 6)])
	return window


def flick_event_ct(rows):
	"""ct of the dominant px/py step (paired samples skipped)."""
	best = None
	for a, b in zip(rows, rows[1:]):
		if b[1] - a[1] < 0.001:
			continue
		d = math.hypot(b[5] - a[5], b[6] - a[6])
		if best is None or d > best[1]:
			best = (b[1], d)
	return best


def events_from_trial(trial, index):
	label = trial["label"]
	cts, rows = dedup_stream(trial["samples"])
	if not rows:
		return []
	group = f"trial-{index}"
	out = []

	if label in EXPECTED_TAPS:
		expected = EXPECTED_TAPS[label]
		peaks = jerk_peaks(cts, rows, PEAK_THRESHOLD)
		by_amp = sorted(peaks, key=lambda p: -p[1])
		accepted = []
		for ct, amp in by_amp:
			if len(accepted) >= expected:
				break
			if all(abs(ct - a[0]) >= TAP_MIN_SEPARATION for a in accepted):
				accepted.append((ct, amp))
		floor = min((amp for _, amp in accepted), default=0)
		for ct, amp in peaks:
			if any(abs(ct - a[0]) < 1e-9 for a in accepted):
				event_label = "tap"
			elif amp < floor * GHOST_AMPLITUDE_RATIO:
				event_label = "noise"
			else:
				continue  # ambiguous — neither clearly a tap nor clearly a ghost
			window = extract_window(cts, rows, ct)
			if window:
				out.append({"label": event_label, "group": group, "trial_label": label,
					"peak_ct": ct, "amp": round(amp, 3), "window": window})
	elif label.startswith("flick-"):
		best = flick_event_ct(rows)
		if best:
			window = extract_window(cts, rows, best[0])
			if window:
				out.append({"label": label, "group": group, "trial_label": label,
					"peak_ct": best[0], "amp": round(best[1], 3), "window": window})
	else:  # noise-still / noise-move
		for ct, amp in jerk_peaks(cts, rows, PEAK_THRESHOLD * 0.7):
			window = extract_window(cts, rows, ct)
			if window:
				out.append({"label": "noise", "group": group, "trial_label": label,
					"peak_ct": ct, "amp": round(amp, 3), "window": window})
	return out


def rest_phase_events(trace_path, trials, ct_offset):
	"""Jerk peaks between trials (hand repositioning = hard negatives)."""
	rows = []
	for line in trace_path.read_text(encoding="utf-8").splitlines():
		rec = json.loads(line)
		if rec.get("type") == "sample":
			rows.append([rec["t"], rec["ct"], rec["x"], rec["y"], rec["z"],
				rec.get("px", 0.0), rec.get("py", 0.0)])
	rows.sort(key=lambda r: r[1])
	cts = [r[1] for r in rows]

	# exclusion zones: every trial window plus margin, in ct time
	zones = sorted((t["goT"] - ct_offset - 0.9, t["endT"] - ct_offset + 0.9) for t in trials)

	def in_zone(ct):
		i = bisect.bisect_right(zones, (ct, float("inf"))) - 1
		return i >= 0 and zones[i][0] <= ct <= zones[i][1]

	session_lo = zones[0][0] - 5
	session_hi = zones[-1][1] + 5
	out = []
	for ct, amp in jerk_peaks(cts, rows, PEAK_THRESHOLD):
		if not (session_lo <= ct <= session_hi) or in_zone(ct):
			continue
		window = extract_window(cts, rows, ct)
		if window:
			out.append({"label": "noise", "group": f"rest-{int(ct)}", "trial_label": "rest-phase",
				"peak_ct": ct, "amp": round(amp, 3), "window": window})
	return out


def main():
	parser = argparse.ArgumentParser(description="Build per-event training data from a labeled session.")
	parser.add_argument("capture_dir", type=Path, nargs="?",
		default=Path(__file__).resolve().parent.parent / "Tools/oura-calibration/captures/20260705-231028")
	parser.add_argument("--out", type=Path, help="Output ndjson (default: <capture>/events.ndjson)")
	args = parser.parse_args()

	dataset_path = args.capture_dir / "gesture-dataset.ndjson"
	trials = [json.loads(l) for l in dataset_path.read_text().splitlines() if l.strip()]
	covered = [t for t in trials if t["samples"]]
	print(f"{len(covered)} covered trials (of {len(trials)})")

	events = []
	for index, trial in enumerate(covered):
		events.extend(events_from_trial(trial, index))

	trace_path = args.capture_dir / "motion-trace.ndjson"
	if trace_path.exists():
		first = covered[0]["samples"][0]
		ct_offset = first[0] - first[1]
		rest = rest_phase_events(trace_path, covered, ct_offset)
		events.extend(rest)
		print(f"rest-phase negatives: {len(rest)}")

	out_path = args.out or (args.capture_dir / "events.ndjson")
	with out_path.open("w", encoding="utf-8") as handle:
		for event in events:
			handle.write(json.dumps(event, separators=(",", ":")) + "\n")

	counts = Counter(e["label"] for e in events)
	print(f"\n{len(events)} events → {out_path}")
	for label, count in sorted(counts.items()):
		print(f"  {label:<12} {count}")


if __name__ == "__main__":
	main()
