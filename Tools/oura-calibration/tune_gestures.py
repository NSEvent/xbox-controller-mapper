#!/usr/bin/env python3
"""Offline replay tuner for the Oura gesture heuristics.

Faithful Python port of the Swift recognizer pipeline (OuraTapDetector,
OuraTapSequenceRecognizer, OuraTapHoldRecognizer, OuraDirectionalFlickRecognizer,
OuraTapMotionSuppressor + the OuraRingInputService glue), replayed over an
archived motion trace so threshold changes can be scored against the prompted
labels from a gestures.html session without touching the ring.

Modes:
  --verify           replay stock params with session-time mappings and diff the
                     emitted events against the events recorded live in the trace
                     (port-fidelity check — run this before trusting any sweep)
  --sweep N          random-restart hill climb, N iterations, production mappings
  (default)          single replay + confusion matrix at stock params

Port-fidelity notes (kept in sync with the Swift sources):
  - `detectedTap = ts >= suppressTapDetectionUntil && tapDetector.register(...)`
    short-circuits: during center suppression the detector's sample history
    freezes. Same for the flick recognizer behind the tapMotionSuppressor gate.
  - Live, the "center" trace event is written after its sample line but its
    suppression applies to that same sample's detection — replay preloads
    center times and applies them at ct <= sample.ct.
  - Whether a gesture is MAPPED changes recognizer state: a mapped tap-hold
    resets the tap sequence (killing the spurious trailing single-tap); mapped
    flicks/holds add post-action suppression. Session fidelity uses the
    mappings in effect during capture (taps mapped, hold/flicks NOT); sweeps
    score with production mappings (everything mapped).
"""
import argparse
import bisect
import json
import math
import random
from dataclasses import dataclass, fields, replace
from pathlib import Path

from analyze_gestures import (
	build_trials,
	latest_gesture_session,
	load_events,
	predicted_outcome,
	slice_window,
)


ROOT = Path(__file__).resolve().parent
DEFAULT_CAPTURE = ROOT / "captures" / "20260705-231028"

PRE_ROLL_SECONDS = 0.35
POST_ROLL_SECONDS = 0.65


# Params defaults mirror the constants the app SHIPPED WITH during the
# 2026-07-05 labeled session — keep them frozen so `--verify` stays
# reproducible against that archive. The tuned constants shipped to the Swift
# code on 2026-07-06 are below in SHIPPED_2026_07_06; to verify a NEW session
# recorded on the tuned build, replay with `replace(Params(), **SHIPPED_2026_07_06)`.
SHIPPED_2026_07_06 = dict(
	det_refractory=0.18, det_quiet_leadin_jerk=1.63, det_peak_jerk=0.44,
	det_peak_magnitude=1.064, det_peak_magnitude_delta=0.05, det_confirm_window=0.145,
	det_peak_drop=0.13, det_settle_ratio=0.92,
	hold_duration=0.6, hold_settle=0.09, hold_max_anchor_drift=0.44, hold_max_sample_step=0.45,
	sequence_window=0.75,  # raised from 0.65 later on 2026-07-06 — live 3x/5x chains split on ~0.7s gaps
)
# hold_duration raised 0.36 → 0.6 same day: still-handed single taps were firing as holds


@dataclass(frozen=True)
class Params:
	# OuraTapDetector
	det_refractory: float = 0.10
	det_max_dt: float = 0.20
	det_quiet_leadin_jerk: float = 0.70
	det_jerk_override_abs: float = 1.35
	det_jerk_override_ratio: float = 2.0
	det_peak_jerk: float = 0.55
	det_peak_magnitude: float = 1.10
	det_peak_magnitude_delta: float = 0.15
	det_confirm_window: float = 0.10
	det_reversal_dot: float = -0.02
	det_peak_drop: float = 0.08
	det_settle_ratio: float = 0.90
	# OuraRingInputService
	accel_tap_refractory: float = 0.16
	center_tap_suppression: float = 0.75
	tap_motion_suppression_extra: float = 0.20  # + sequence_window
	post_action_suppression: float = 0.18
	# OuraTapSequenceRecognizer
	sequence_window: float = 0.65
	duplicate_window: float = 0.09
	max_tap_count: int = 5
	timer_slack: float = 0.02
	# OuraTapHoldRecognizer
	hold_duration: float = 0.42
	hold_settle: float = 0.16
	hold_min_still: float = 0.22
	hold_max_duration: float = 1.2
	hold_max_anchor_drift: float = 0.34
	hold_max_sample_step: float = 0.28
	# OuraDirectionalFlickRecognizer
	flick_return_threshold: float = 0.24
	flick_min_snap_distance: float = 0.48
	flick_min_snap_velocity: float = 2.4
	flick_axis_dominance: float = 1.55
	flick_max_snap_duration: float = 0.32
	flick_max_return_duration: float = 0.45
	flick_cooldown: float = 0.65
	# structural: gate flick registration behind the tap-motion suppressor
	# (True matches the shipped code; False quantifies removing the gate)
	flick_gate_by_suppression: bool = True


SWEEP_RANGES = {
	"det_quiet_leadin_jerk": (0.30, 1.50),
	"det_jerk_override_abs": (0.80, 2.50),
	"det_peak_jerk": (0.30, 1.20),
	"det_peak_magnitude": (1.00, 1.40),
	"det_peak_magnitude_delta": (0.05, 0.35),
	"det_confirm_window": (0.06, 0.20),
	"det_peak_drop": (0.02, 0.20),
	"det_settle_ratio": (0.60, 1.20),
	"det_refractory": (0.06, 0.20),
	"accel_tap_refractory": (0.08, 0.30),
	"sequence_window": (0.35, 0.90),
	"duplicate_window": (0.04, 0.20),
	"tap_motion_suppression_extra": (-0.40, 0.40),
	"hold_duration": (0.30, 0.70),
	"hold_settle": (0.08, 0.30),
	"hold_min_still": (0.10, 0.40),
	"hold_max_anchor_drift": (0.15, 0.50),
	"hold_max_sample_step": (0.15, 0.50),
	"flick_return_threshold": (0.10, 0.50),
	"flick_min_snap_distance": (0.20, 0.80),
	"flick_min_snap_velocity": (0.80, 4.00),
	"flick_axis_dominance": (1.10, 2.50),
	"flick_max_snap_duration": (0.15, 0.60),
	"flick_max_return_duration": (0.20, 1.00),
	"flick_cooldown": (0.30, 1.00),
	"flick_gate_by_suppression": (False, True),
}


@dataclass(frozen=True)
class Mappings:
	double_tap: bool = True
	triple_tap: bool = True
	tap_hold: bool = True
	flicks: bool = True


SESSION_MAPPINGS = Mappings(tap_hold=False, flicks=False)
PRODUCTION_MAPPINGS = Mappings()


def hypot3(x, y, z):
	return math.sqrt(x * x + y * y + z * z)


class TapDetector:
	def __init__(self, p):
		self.p = p
		self.sample_before_previous = None
		self.previous_sample = None
		self.pending = None  # (prev_sample, sample, delta, peak_magnitude)
		self.last_tap_time = 0.0

	def register(self, s):
		# s = (ct, x, y, z)
		try:
			p = self.p
			if self.pending is not None:
				if self._confirms(self.pending, s):
					self.pending = None
					self.last_tap_time = s[0]
					return True
				if s[0] - self.pending[1][0] > p.det_confirm_window:
					self.pending = None

			prev = self.previous_sample
			if prev is None:
				return False
			if s[0] - self.last_tap_time <= p.det_refractory:
				return False

			dt = s[0] - prev[0]
			if not (0 < dt < p.det_max_dt):
				return False

			delta = (s[1] - prev[1], s[2] - prev[2], s[3] - prev[3])
			jerk = hypot3(*delta)
			magnitude = hypot3(s[1], s[2], s[3])
			previous_magnitude = hypot3(prev[1], prev[2], prev[3])
			magnitude_delta = abs(magnitude - previous_magnitude)
			before = self.sample_before_previous
			if before is None:
				return False
			lead_in_jerk = hypot3(prev[1] - before[1], prev[2] - before[2], prev[3] - before[3])
			quiet_lead_in = (lead_in_jerk < p.det_quiet_leadin_jerk or
				jerk > max(p.det_jerk_override_abs, lead_in_jerk * p.det_jerk_override_ratio))
			sharp_peak = (jerk > p.det_peak_jerk and magnitude > p.det_peak_magnitude and
				magnitude_delta > p.det_peak_magnitude_delta)

			if quiet_lead_in and sharp_peak:
				self.pending = (prev, s, delta, magnitude)
			return False
		finally:
			self.sample_before_previous = self.previous_sample
			self.previous_sample = s

	def _confirms(self, pending, s):
		p = self.p
		prev_sample, cand, delta, peak_magnitude = pending
		dt = s[0] - cand[0]
		if not (0 < dt <= p.det_confirm_window):
			return False
		follow = (s[1] - cand[1], s[2] - cand[2], s[3] - cand[3])
		magnitude = hypot3(s[1], s[2], s[3])
		peak_drop = peak_magnitude - magnitude
		reversal = (delta[0] * follow[0] + delta[1] * follow[1] + delta[2] * follow[2]) < p.det_reversal_dot
		settled = hypot3(s[1] - prev_sample[1], s[2] - prev_sample[2], s[3] - prev_sample[3])
		return reversal and (peak_drop > p.det_peak_drop or settled < hypot3(*delta) * p.det_settle_ratio)


class TapSequence:
	def __init__(self, p):
		self.p = p
		self.tap_count = 0
		self.last_tap_time = None
		self.last_accepted_tap_time = None

	def reset(self):
		self.tap_count = 0
		self.last_tap_time = None
		self.last_accepted_tap_time = None

	def register_tap(self, ts):
		p = self.p
		if self.last_accepted_tap_time is not None and ts - self.last_accepted_tap_time < p.duplicate_window:
			return ("duplicate", 0)
		if self.last_tap_time is not None and ts - self.last_tap_time <= p.sequence_window:
			self.tap_count += 1
		else:
			self.tap_count = 1
		self.last_tap_time = ts
		self.last_accepted_tap_time = ts
		if self.tap_count >= p.max_tap_count:
			completed = self.tap_count
			self.tap_count = 0
			self.last_tap_time = None
			return ("completed", completed)
		return ("pending", self.tap_count)

	def resolve_pending(self, ts):
		if self.last_tap_time is None or ts - self.last_tap_time < self.p.sequence_window:
			return None
		resolved = self.tap_count
		self.tap_count = 0
		self.last_tap_time = None
		return resolved if resolved > 0 else None


class TapHold:
	def __init__(self, p):
		self.p = p
		self.candidate = None  # [start_time, anchor, anchor_time]
		self.previous_sample = None

	def register_tap(self, ts, sample):
		if sample is None:
			self.candidate = None
			self.previous_sample = None
			return
		self.candidate = [ts, None, None]
		self.previous_sample = sample

	def cancel(self):
		self.candidate = None

	def register_motion(self, s):
		try:
			p = self.p
			cand = self.candidate
			if cand is None:
				return False
			elapsed = s[0] - cand[0]
			if elapsed < 0:
				return False
			if elapsed > p.hold_max_duration:
				self.candidate = None
				return False
			if elapsed < p.hold_settle:
				return False
			if cand[1] is None:
				cand[1] = s
				cand[2] = s[0]
				return False
			anchor, anchor_time = cand[1], cand[2]
			if self._dist(s, anchor) > p.hold_max_anchor_drift:
				self.candidate = None
				return False
			prev = self.previous_sample
			if prev is not None and prev[0] >= anchor_time and self._dist(s, prev) > p.hold_max_sample_step:
				self.candidate = None
				return False
			if elapsed < p.hold_duration or s[0] - anchor_time < p.hold_min_still:
				return False
			self.candidate = None
			return True
		finally:
			self.previous_sample = s

	def _dist(self, a, b):
		return hypot3(a[1] - b[1], a[2] - b[2], a[3] - b[3])


class Flick:
	def __init__(self, p):
		self.p = p
		self.previous_point = None
		self.previous_timestamp = None
		self.candidate = None  # (direction, start_time, peak_time, start, peak)
		self.cooldown_until = 0.0

	def register(self, point, ts):
		try:
			p = self.p
			if ts < self.cooldown_until:
				return None
			if self.candidate is not None:
				return self._update(point, ts)
			if self.previous_point is None or self.previous_timestamp is None:
				return None
			dt = ts - self.previous_timestamp
			if not (0 < dt <= p.flick_max_snap_duration):
				return None
			dx = point[0] - self.previous_point[0]
			dy = point[1] - self.previous_point[1]
			snap = math.hypot(dx, dy)
			if snap < p.flick_min_snap_distance or snap / dt < p.flick_min_snap_velocity:
				return None
			direction = self._dominant(dx, dy)
			if direction is None:
				return None
			self.candidate = (direction, self.previous_timestamp, ts, self.previous_point, point)
			return None
		finally:
			self.previous_point = point
			self.previous_timestamp = ts

	def _update(self, point, ts):
		p = self.p
		direction, start_time, peak_time, start, peak = self.candidate
		if ts - peak_time > p.flick_max_return_duration:
			self.candidate = None
			return None
		if math.dist(point, start) > math.dist(peak, start):
			peak_time, peak = ts, point
			self.candidate = (direction, start_time, peak_time, start, peak)
		if math.dist(point, start) > p.flick_return_threshold:
			return None
		self.candidate = None
		self.cooldown_until = ts + p.flick_cooldown
		return direction

	def _dominant(self, dx, dy):
		ax, ay = abs(dx), abs(dy)
		if ax > ay * self.p.flick_axis_dominance:
			return "right" if dx > 0 else "left"
		if ay > ax * self.p.flick_axis_dominance:
			return "up" if dy > 0 else "down"
		return None


class Service:
	"""OuraRingInputService glue, virtual-time event-driven."""

	def __init__(self, params, mappings):
		self.p = params
		self.m = mappings
		self.detector = TapDetector(params)
		self.sequence = TapSequence(params)
		self.hold = TapHold(params)
		self.flick = Flick(params)
		self.suppress_until = 0.0          # OuraTapMotionSuppressor
		self.suppress_tap_until = 0.0      # center-based detector gate
		self.last_accel_tap_time = 0.0
		self.resolution_at = None          # scheduled sequence-resolution time
		self.events = []                   # (ct, name, detail)

	def _suppress_motion(self, ts, duration):
		self.suppress_until = max(self.suppress_until, ts + duration)

	def fire_due_timers(self, now):
		if self.resolution_at is not None and now >= self.resolution_at:
			at = self.resolution_at
			self.resolution_at = None
			resolved = self.sequence.resolve_pending(at)
			if resolved is not None:
				self._perform_tap_action(resolved, at)

	def feed_center(self, ct):
		self.suppress_tap_until = max(self.suppress_tap_until, ct + self.p.center_tap_suppression)

	def feed_sample(self, ct, x, y, z, px, py):
		s = (ct, x, y, z)
		detected = ct >= self.suppress_tap_until and self.detector.register(s)
		if detected:
			self.events.append((ct, "tap-detected", None))
			self._handle_accel_tap(ct, s)
		else:
			self._handle_hold(s)
			self._handle_flick((px, py), ct)

	def _handle_accel_tap(self, ts, sample):
		if ts - self.last_accel_tap_time <= self.p.accel_tap_refractory:
			return
		self.last_accel_tap_time = ts
		self._handle_tap_candidate(ts, sample)

	def _handle_tap_candidate(self, ts, sample):
		self.events.append((ts, "tap-candidate", "accelerometer spike"))
		kind, count = self.sequence.register_tap(ts)
		if kind == "duplicate":
			return
		if kind == "pending":
			if count == 1:
				self.hold.register_tap(ts, sample)
			else:
				self.hold.cancel()
			self._suppress_motion(ts, self.p.sequence_window + self.p.tap_motion_suppression_extra)
			self.resolution_at = ts + self.p.sequence_window + self.p.timer_slack
		else:  # completed
			self.hold.cancel()
			self.resolution_at = None
			self._suppress_motion(ts, self.p.post_action_suppression)
			self._perform_tap_action(count, ts)

	def _perform_tap_action(self, count, now):
		self.resolution_at = None
		self.hold.cancel()
		self._suppress_motion(now, self.p.post_action_suppression)
		self.events.append((now, "tap-resolved", str(count)))

	def _handle_hold(self, s):
		if not self.hold.register_motion(s):
			return
		self.events.append((s[0], "tap-hold", None))
		if self.m.tap_hold:
			self.resolution_at = None
			self.sequence.reset()
			self._suppress_motion(s[0], self.p.post_action_suppression)

	def _handle_flick(self, point, ts):
		if self.p.flick_gate_by_suppression and ts < self.suppress_until:
			return
		direction = self.flick.register(point, ts)
		if direction is None:
			return
		self.events.append((ts, "flick", direction))
		if self.m.flicks:
			self._suppress_motion(ts, self.p.post_action_suppression)


def split_by_coverage(trials, samples):
	"""A prompted window with no trace samples is lost data, not a recognition
	miss — split it out so scoring only sees trials the recognizers could see."""
	times = sorted(s[6] for s in samples)
	covered, dropped = [], []
	for trial in trials:
		lo, hi = trial["goT"] - PRE_ROLL_SECONDS, trial["endT"] + POST_ROLL_SECONDS
		i = bisect.bisect_left(times, lo)
		(covered if i < len(times) and times[i] <= hi else dropped).append(trial)
	return covered, dropped


def load_trace(trace_path):
	samples = []       # (ct, x, y, z, px, py, t)
	live_events = []   # (ct, name, detail, t)
	center_times = []
	for line in trace_path.read_text(encoding="utf-8").splitlines():
		if not line.strip():
			continue
		record = json.loads(line)
		if record.get("type") == "sample":
			samples.append((record["ct"], record["x"], record["y"], record["z"],
				record.get("px", 0.0), record.get("py", 0.0), record["t"]))
		elif record.get("type") == "event":
			live_events.append((record["ct"], record["name"], record.get("detail"), record["t"]))
			if record["name"] == "center":
				center_times.append(record["ct"])
	return samples, live_events, sorted(center_times)


def replay(samples, center_times, params, mappings):
	service = Service(params, mappings)
	center_index = 0
	for s in samples:
		ct = s[0]
		while center_index < len(center_times) and center_times[center_index] <= ct:
			service.feed_center(center_times[center_index])
			center_index += 1
		service.fire_due_timers(ct)
		service.feed_sample(ct, s[1], s[2], s[3], s[4], s[5])
	if samples:
		service.fire_due_timers(samples[-1][0] + 5.0)
	return service.events


def score(trials, events, ct_offset):
	"""events: (ct, name, detail) → score against trial windows (unix time)."""
	dicts = [{"t": ct + ct_offset, "name": name, "detail": detail}
		for ct, name, detail in events if name in ("tap-resolved", "flick", "tap-hold")]
	correct = 0
	noise_clean = True
	rows = {}
	for trial in trials:
		window = slice_window(dicts, trial["goT"] - PRE_ROLL_SECONDS, trial["endT"] + POST_ROLL_SECONDS)
		prediction = predicted_outcome(window)
		expected = "none" if trial["expect"].get("none") else trial["label"]
		rows.setdefault(expected, []).append(prediction)
		if prediction == expected:
			correct += 1
		elif expected == "none":
			noise_clean = False
	return correct, noise_clean, rows


def print_confusion(rows, total_correct, total):
	width = max(len(k) for k in rows) + 2
	for expected in sorted(rows):
		preds = rows[expected]
		hits = sum(1 for p in preds if p == expected)
		counts = {}
		for p in preds:
			counts[p] = counts.get(p, 0) + 1
		parts = ", ".join(f"{k}×{v}" for k, v in sorted(counts.items(), key=lambda kv: -kv[1]))
		print(f"  {expected:<{width}} {hits}/{len(preds)}   [{parts}]")
	print(f"  Overall: {total_correct}/{total} ({100 * total_correct / total:.0f}%)")


def verify(samples, live_events, center_times, trials, ct_offset):
	print("== Port fidelity: replay (stock params, session mappings) vs live events ==")
	emitted = replay(samples, center_times, Params(), SESSION_MAPPINGS)
	tolerance = 0.06
	for name in ("tap-detected", "tap-candidate", "tap-resolved", "flick", "tap-hold"):
		live = [(ct, detail) for ct, n, detail, _ in live_events if n == name]
		mine = [(ct, detail) for ct, n, detail in emitted if n == name]
		unmatched_live = list(live)
		matched = 0
		for ct, detail in mine:
			for i, (lct, ldetail) in enumerate(unmatched_live):
				if abs(lct - ct) <= tolerance and ldetail == detail:
					unmatched_live.pop(i)
					matched += 1
					break
		print(f"  {name:<14} live {len(live):>3}  replay {len(mine):>3}  matched {matched:>3}"
			+ ("" if len(live) == len(mine) == matched else "  ← MISMATCH"))
	correct, noise_clean, rows = score(trials, emitted, ct_offset)
	print("\n== Replayed confusion (should ≈ live analyzer output) ==")
	print_confusion(rows, correct, len(trials))


def mutate(base, rng, n_params):
	updates = {}
	for key in rng.sample(list(SWEEP_RANGES), n_params):
		lo, hi = SWEEP_RANGES[key]
		if isinstance(lo, bool):
			updates[key] = rng.random() < 0.5
		else:
			updates[key] = round(rng.uniform(lo, hi), 4)
	return replace(base, **updates)


def sweep(samples, center_times, trials, ct_offset, iterations, seed):
	rng = random.Random(seed)
	stock = Params()
	best = stock
	best_correct, noise_clean, _ = score(trials, replay(samples, center_times, stock, PRODUCTION_MAPPINGS), ct_offset)
	if not noise_clean:
		best_correct = -1
	print(f"Baseline (stock params, production mappings): {best_correct}/{len(trials)}")
	for i in range(iterations):
		candidate = mutate(best if rng.random() < 0.8 else stock, rng, rng.randint(2, 8))
		correct, clean, _ = score(trials, replay(samples, center_times, candidate, PRODUCTION_MAPPINGS), ct_offset)
		if not clean:
			continue
		if correct > best_correct:
			best_correct = correct
			best = candidate
			print(f"  iter {i:>4}: {correct}/{len(trials)} "
				+ ", ".join(f"{f.name}={getattr(candidate, f.name)}"
					for f in fields(Params) if getattr(candidate, f.name) != getattr(stock, f.name)))
	print(f"\n== Best config: {best_correct}/{len(trials)} "
		f"({100 * best_correct / len(trials):.0f}%) — diffs from stock ==")
	for f in fields(Params):
		if getattr(best, f.name) != getattr(stock, f.name):
			print(f"  {f.name}: {getattr(stock, f.name)} → {getattr(best, f.name)}")
	correct, _, rows = score(trials, replay(samples, center_times, best, PRODUCTION_MAPPINGS), ct_offset)
	print_confusion(rows, correct, len(trials))
	return best


def main():
	parser = argparse.ArgumentParser(description="Replay-tune Oura gesture heuristics against a labeled session.")
	parser.add_argument("capture_dir", nargs="?", type=Path, default=DEFAULT_CAPTURE)
	parser.add_argument("--trace", type=Path, help="Archived trace (default: <capture>/motion-trace.ndjson)")
	parser.add_argument("--verify", action="store_true", help="Port-fidelity check vs live events")
	parser.add_argument("--sweep", type=int, metavar="N", help="Random-search iterations")
	parser.add_argument("--seed", type=int, default=7)
	args = parser.parse_args()

	trace_path = args.trace or (args.capture_dir / "motion-trace.ndjson")
	samples, live_events, center_times = load_trace(trace_path)
	trials = build_trials(latest_gesture_session(load_events(args.capture_dir)))
	ct_offset = sum(s[6] - s[0] for s in samples[:200]) / min(len(samples), 200)
	trials, dropped = split_by_coverage(trials, samples)
	print(f"Trace: {trace_path} ({len(samples)} samples, {len(live_events)} live events, "
		f"{len(center_times)} centers) — {len(trials)} trials with coverage"
		+ (f", {len(dropped)} excluded (no trace samples in window)" if dropped else "") + "\n")

	if args.verify:
		verify(samples, live_events, center_times, trials, ct_offset)
	elif args.sweep:
		sweep(samples, center_times, trials, ct_offset, args.sweep, args.seed)
	else:
		correct, _, rows = score(trials, replay(samples, center_times, Params(), SESSION_MAPPINGS), ct_offset)
		print_confusion(rows, correct, len(trials))


if __name__ == "__main__":
	main()
