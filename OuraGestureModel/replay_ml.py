#!/usr/bin/env python3
"""End-to-end replay of the ML gesture pipeline against a labeled session.

Simulates exactly what the Swift integration will do, sample by sample:
  jerk-impulse candidate detector (mirrors build_dataset extraction)
  → pending-window queue (classify at peak+0.38s)
  → OuraGestureNet
  → tap: tuned OuraTapSequenceRecognizer counting (+ tap-hold recognizer)
    flick: direct fire + impulse cooldown
    noise: drop
then scores prompted trial windows with the same confusion logic as
tune_gestures.py.

Honesty note: replaying the session the model TRAINED on validates the
plumbing (candidate recall, window timing, counting, cooldowns), not
generalization — the grouped-CV numbers in train.py are the performance claim.
"""
import bisect
import json
import sys
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent / "Tools" / "oura-calibration"))

from model import CLASSES, OuraGestureNet
from build_dataset import extract_window, PEAK_MIN_SEPARATION, PEAK_THRESHOLD, WINDOW_POST
from tune_gestures import (Params, SHIPPED_2026_07_06, TapSequence, TapHold,
	load_trace, score, print_confusion, build_trials, latest_gesture_session,
	load_events, split_by_coverage)
from dataclasses import replace

FLICK_COOLDOWN = 0.65
FLICK_CONFIDENCE_THRESHOLD = 0.5
CENTER_SUPPRESSION = 0.75


class MLPipeline:
	def __init__(self, model, params):
		self.model = model
		self.p = params
		self.sequence = TapSequence(params)
		self.hold = TapHold(params)
		self.rows = []            # [t, ct, x, y, z, px, py] history
		self.cts = []
		self.jerk_prev = None     # (ct, jerk) of previous jerk-series entry
		self.jerk_before = None
		self.last_peak_ct = -1e9
		self.pending_peaks = []   # peak cts waiting for their window to complete
		self.cooldown_until = 0.0
		self.suppress_until = 0.0
		self.resolution_at = None
		self.hold_fed_ct = -1e9   # newest ct the hold recognizer has consumed
		self.events = []          # (ct, name, detail)

	def feed_center(self, ct):
		self.suppress_until = max(self.suppress_until, ct + CENTER_SUPPRESSION)

	def fire_due_timers(self, now):
		if self.resolution_at is not None and now >= self.resolution_at:
			if self.pending_peaks:
				# a candidate is mid-classification — it may extend the tap
				# sequence, so defer resolution until its window completes
				self.resolution_at = self.pending_peaks[0] + WINDOW_POST + 0.05
				return
			at = self.resolution_at
			self.resolution_at = None
			resolved = self.sequence.resolve_pending(at)
			if resolved is not None:
				self.hold.cancel()
				self.events.append((at, "tap-resolved", str(resolved)))

	def feed_sample(self, t, ct, x, y, z, px, py):
		self.rows.append([t, ct, x, y, z, px, py])
		self.cts.append(ct)

		# classify any pending peak whose window is now complete
		while self.pending_peaks and ct >= self.pending_peaks[0] + WINDOW_POST:
			self._classify(self.pending_peaks.pop(0), now=ct)

		# jerk series (skip paired samples <1ms apart), 1-sample-lookahead peak confirm
		if len(self.rows) >= 2:
			a, b = self.rows[-2], self.rows[-1]
			if b[1] - a[1] >= 0.001:
				j = ((b[2] - a[2]) ** 2 + (b[3] - a[3]) ** 2 + (b[4] - a[4]) ** 2) ** 0.5
				entry = (b[1], j)
				if self.jerk_before and self.jerk_prev:
					p_ct, p_j = self.jerk_prev
					if (p_j >= PEAK_THRESHOLD and p_j >= self.jerk_before[1] and p_j >= j
							and p_ct - self.last_peak_ct >= PEAK_MIN_SEPARATION
							and p_ct >= self.suppress_until
							and p_ct >= self.cooldown_until):
						self.last_peak_ct = p_ct
						self.pending_peaks.append(p_ct)
				self.jerk_before = self.jerk_prev
				self.jerk_prev = entry

		# tap-hold needs the motion stream (same as the heuristic pipeline);
		# skip samples the retroactive catch-up already consumed
		if ct > self.hold_fed_ct:
			self.hold_fed_ct = ct
			if self.hold.register_motion((ct, x, y, z)):
				self.events.append((ct, "tap-hold", None))
				self.resolution_at = None
				self.sequence.reset()

	def _classify(self, peak_ct, now):
		if peak_ct < self.cooldown_until:
			return  # previous flick's echo — already-queued peaks skip the enqueue check
		window = extract_window(self.cts, self.rows, peak_ct)
		if window is None:
			return
		with torch.no_grad():
			logits = self.model(torch.tensor(np.array([window], dtype=np.float32)))
		probs = torch.softmax(logits, dim=1)[0]
		label = CLASSES[int(probs.argmax())]
		confidence = float(probs.max())
		self.events.append((peak_ct, "ml-class", label))
		if label == "tap":
			kind, count = self.sequence.register_tap(peak_ct)
			if kind == "duplicate":
				return
			if kind == "pending":
				if count == 1:
					self._start_hold_retroactively(peak_ct)
				else:
					self.hold.cancel()
				self.resolution_at = max(now, peak_ct + self.p.sequence_window) + self.p.timer_slack
			else:
				self.hold.cancel()
				self.resolution_at = None
				self.events.append((now, "tap-resolved", str(count)))
		elif label.startswith("flick-"):
			# Mirror the Swift gates (phantom-flick fix, 2026-07-06): drop
			# low-confidence flicks; consume a pending tap only when it falls
			# inside the flick's own window (its outbound spike).
			if confidence < FLICK_CONFIDENCE_THRESHOLD:
				return
			if self.sequence.tap_count > 0 and self.sequence.last_tap_time is not None \
					and peak_ct - self.sequence.last_tap_time <= 0.64:
				self.sequence.reset()
				self.resolution_at = None
				self.hold.cancel()
			self.events.append((now, "flick", label.split("-")[1]))
			self.cooldown_until = peak_ct + FLICK_COOLDOWN
			self.hold.cancel()
		# noise → drop

	def _start_hold_retroactively(self, peak_ct):
		"""Classification arrives ~0.4s after the tap; anchor the hold candidate
		back at the peak and replay the buffered samples since, so hold timing
		(settle at +0.09, ring-down drift checks) matches the heuristic path.
		The Swift integration does the same from its ring buffer."""
		i = bisect.bisect_left(self.cts, peak_ct)
		if i >= len(self.rows):
			return
		row = self.rows[i]
		self.hold.register_tap(peak_ct, (row[1], row[2], row[3], row[4]))
		for r in self.rows[i + 1:]:
			self.hold_fed_ct = max(self.hold_fed_ct, r[1])
			if self.hold.register_motion((r[1], r[2], r[3], r[4])):
				self.events.append((r[1], "tap-hold", None))
				self.resolution_at = None
				self.sequence.reset()
				break


def main():
	capture = Path(sys.argv[1]) if len(sys.argv) > 1 else \
		ROOT.parent / "Tools/oura-calibration/captures/20260705-231028"

	checkpoint = torch.load(ROOT / "checkpoints/oura_gesture.pt", weights_only=True)
	model = OuraGestureNet()
	model.load_state_dict(checkpoint["state_dict"])
	model.eval()

	samples, _, centers = load_trace(capture / "motion-trace.ndjson")
	trials, dropped = split_by_coverage(
		build_trials(latest_gesture_session(load_events(capture))), samples)
	ct_offset = sum(s[6] - s[0] for s in samples[:200]) / 200
	params = replace(Params(), **SHIPPED_2026_07_06)

	pipeline = MLPipeline(model, params)
	center_index = 0
	for s in samples:  # (ct, x, y, z, px, py, t)
		ct = s[0]
		while center_index < len(centers) and centers[center_index] <= ct:
			pipeline.feed_center(centers[center_index])
			center_index += 1
		pipeline.fire_due_timers(ct)
		pipeline.feed_sample(s[6], ct, s[1], s[2], s[3], s[4], s[5])
	pipeline.fire_due_timers(samples[-1][0] + 5.0)

	correct, clean, rows = score(trials, pipeline.events, ct_offset)
	tap_classes = ("single-tap", "double-tap", "triple-tap", "five-tap", "tap-hold")
	th = sum(sum(1 for p in rows.get(c, []) if p == c) for c in tap_classes)
	tt = sum(len(rows.get(c, [])) for c in tap_classes)
	flick_classes = tuple(c for c in rows if c.startswith("flick"))
	fh = sum(sum(1 for p in rows.get(c, []) if p == c) for c in flick_classes)
	ft = sum(len(rows.get(c, [])) for c in flick_classes)
	print(f"ML pipeline replay on {len(trials)} covered trials "
		f"({len(dropped)} excluded) — TRAINING-SESSION replay, see CV for generalization:")
	print(f"  overall {correct}/{len(trials)} | taps+hold {th}/{tt} | flicks {fh}/{ft} | noise-clean={clean}\n")
	print_confusion(rows, correct, len(trials))


if __name__ == "__main__":
	main()
