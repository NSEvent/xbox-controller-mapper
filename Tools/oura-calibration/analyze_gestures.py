#!/usr/bin/env python3
"""Join a gesture-labeling session (gestures.html) with the app's full-rate
motion trace, score the current recognizers against the prompted labels, and
export a labeled dataset for classifier training.

Inputs:
  - <capture>/targets.ndjson  — prompt events from serve.py (trial:go/end etc.)
  - the app-side trace         — ndjson written by OuraMotionTraceWriter when
    `defaults write KevinTang.XboxControllerMapper ouraMotionTraceLogging -bool true`
    is set (default /tmp/controllerkeys-oura-motion-trace.ndjson)

Both sides record wall-clock unix seconds ("t" in the trace, wallTimeUnix in
the prompt events), so the join is a plain time-window slice. Trace "ct"
values (CFAbsoluteTime) are stamped at BLE-frame decode, so the two samples
in one frame share a near-identical ct — sample-rate stats below dedupe those
pairs into frames before measuring spacing.
"""
import argparse
import json
import math
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DEFAULT_CAPTURE_ROOT = ROOT / "captures"
DEFAULT_TRACE = Path("/tmp/controllerkeys-oura-motion-trace.ndjson")

PRE_ROLL_SECONDS = 0.35
POST_ROLL_SECONDS = 0.65
FRAME_PAIR_EPSILON = 0.002

TAP_COUNT_LABELS = {1: "single-tap", 2: "double-tap", 3: "triple-tap", 5: "five-tap"}


def latest_capture_dir(root):
	candidates = sorted(path for path in root.glob("*") if (path / "targets.ndjson").exists())
	if not candidates:
		raise SystemExit(f"No captures found under {root}")
	return candidates[-1]


def load_events(capture_dir):
	events_path = capture_dir / "targets.ndjson"
	if not events_path.exists():
		raise SystemExit(f"Missing {events_path}")
	events = []
	for line in events_path.read_text(encoding="utf-8").splitlines():
		if line.strip():
			events.append(json.loads(line))
	return events


def event_seconds(event):
	if "wallTimeUnix" in event:
		return float(event["wallTimeUnix"])
	return float(event["serverReceivedUnix"])


def latest_gesture_session(events):
	start_index = None
	for index, event in enumerate(events):
		if event.get("type") == "session:start" and event.get("kind") == "gesture-labeling":
			start_index = index
	if start_index is None:
		raise SystemExit(
			"No gesture-labeling session in this capture. Pass the right capture dir "
			"(each serve.py launch makes a fresh one) or run gestures.html first."
		)
	for end_index in range(start_index + 1, len(events)):
		if events[end_index].get("type") == "session:end":
			return events[start_index:end_index + 1]
	return events[start_index:]


def build_trials(session_events):
	"""Replay the event stream: go→end pairs complete a trial, discards drop
	the pending or most recent one. trialIndex values are reused after a
	mid-trial discard, so sequential replay is the only safe join."""
	completed = []
	pending = None
	for event in session_events:
		event_type = event.get("type")
		if event_type == "trial:go":
			pending = event
		elif event_type == "trial:end":
			if pending and pending.get("label") == event.get("label"):
				completed.append({
					"label": pending["label"],
					"expect": pending.get("expect", {}),
					"windowSeconds": pending.get("windowSeconds"),
					"goT": event_seconds(pending),
					"endT": event_seconds(event),
				})
			pending = None
		elif event_type == "trial:discard":
			if event.get("scope") == "current":
				pending = None
			elif completed:
				completed.pop()
	return completed


def load_trace(trace_path, start_time, end_time):
	if not trace_path.exists():
		raise SystemExit(
			f"Missing trace {trace_path} — was ouraMotionTraceLogging enabled "
			"(and ControllerKeys restarted) before the session?"
		)
	samples = []
	trace_events = []
	pad = 5.0
	for line in trace_path.read_text(encoding="utf-8", errors="replace").splitlines():
		line = line.strip()
		if not line:
			continue
		try:
			record = json.loads(line)
		except json.JSONDecodeError:
			continue
		t = record.get("t")
		if t is None or t < start_time - pad or t > end_time + pad:
			continue
		if record.get("type") == "sample":
			samples.append(record)
		elif record.get("type") == "event":
			trace_events.append(record)
	return samples, trace_events


def group_frames(samples):
	"""Collapse paired-timestamp samples (2 per BLE frame, near-identical ct)
	into frames so spacing stats reflect radio cadence, not the decode stamp."""
	frames = []
	for sample in samples:
		if frames and abs(sample["ct"] - frames[-1][-1]["ct"]) < FRAME_PAIR_EPSILON:
			frames[-1].append(sample)
		else:
			frames.append([sample])
	return frames


def percentile(sorted_values, fraction):
	if not sorted_values:
		return 0.0
	index = min(len(sorted_values) - 1, int(fraction * len(sorted_values)))
	return sorted_values[index]


def report_sample_rate(samples):
	print("\n== Sample-rate (the make-or-break number for ML viability) ==")
	if len(samples) < 10:
		print(f"  Only {len(samples)} trace samples in the session window — trace flag off, "
			"ring disconnected, or clock mismatch. Cannot measure.")
		return
	frames = group_frames(samples)
	duration = samples[-1]["ct"] - samples[0]["ct"]
	if duration <= 0:
		print("  Degenerate trace timestamps; cannot measure.")
		return
	samples_per_frame = Counter(len(frame) for frame in frames)
	frame_dts = sorted(
		frames[i][0]["ct"] - frames[i - 1][0]["ct"]
		for i in range(1, len(frames))
	)
	median_dt = percentile(frame_dts, 0.5)
	gaps = [dt for dt in frame_dts if median_dt > 0 and dt > 3 * median_dt]
	print(f"  {len(samples)} samples in {len(frames)} BLE frames over {duration:.1f}s")
	print(f"  Samples per frame: {dict(sorted(samples_per_frame.items()))}")
	print(f"  Frame rate: {len(frames) / duration:.1f} Hz → effective sample rate ~{len(samples) / duration:.1f} Hz")
	print(f"  Inter-frame dt: median {median_dt * 1000:.1f}ms, p95 {percentile(frame_dts, 0.95) * 1000:.1f}ms, max {frame_dts[-1] * 1000:.1f}ms")
	if gaps:
		print(f"  ⚠ {len(gaps)} gaps >3× median ({max(gaps) * 1000:.0f}ms worst) — check BLE link stability")
	rate = len(samples) / duration
	if rate < 20:
		print(f"  ⚠ ~{rate:.0f} Hz is thin for tap discrimination (tap transient ≈ 20-50ms); "
			"an ML classifier will be working from envelope shape, not the transient itself.")


def predicted_outcome(events_in_window):
	"""Map recognizer trace events inside a trial window to a label-space
	prediction. Multiple distinct outcomes are joined with '+', which is
	itself a misfire signal."""
	outcomes = []
	for event in events_in_window:
		name = event.get("name")
		detail = event.get("detail")
		if name == "tap-resolved":
			count = int(detail) if detail and detail.isdigit() else 0
			outcomes.append(TAP_COUNT_LABELS.get(count, f"{count}-tap"))
		elif name == "flick":
			outcomes.append(f"flick-{detail}" if detail else "flick")
		elif name == "tap-hold":
			outcomes.append("tap-hold")
	if not outcomes:
		return "none"
	deduped = list(dict.fromkeys(outcomes))
	return "+".join(deduped)


def slice_window(records, start, end, key="t"):
	return [record for record in records if start <= record[key] <= end]


def report_confusion(trials, trace_events):
	print("\n== Recognizer vs prompt (current heuristics) ==")
	matrix = defaultdict(Counter)
	correct = 0
	for trial in trials:
		window_events = slice_window(
			trace_events, trial["goT"] - PRE_ROLL_SECONDS, trial["endT"] + POST_ROLL_SECONDS)
		recognized = [e for e in window_events if e.get("name") in ("tap-resolved", "flick", "tap-hold")]
		prediction = predicted_outcome(recognized)
		trial["predicted"] = prediction
		expected = "none" if trial["expect"].get("none") else trial["label"]
		matrix[expected][prediction] += 1
		if prediction == expected:
			correct += 1

	label_width = max((len(label) for label in matrix), default=10) + 2
	for expected in sorted(matrix):
		row = matrix[expected]
		total = sum(row.values())
		hits = row.get(expected, 0)
		parts = ", ".join(f"{pred}×{count}" for pred, count in row.most_common())
		print(f"  {expected:<{label_width}} {hits}/{total} correct   [{parts}]")
	if trials:
		print(f"  Overall: {correct}/{len(trials)} ({100 * correct / len(trials):.0f}%)")


def export_dataset(trials, samples, trace_events, export_path):
	with export_path.open("w", encoding="utf-8") as handle:
		for index, trial in enumerate(trials):
			start = trial["goT"] - PRE_ROLL_SECONDS
			end = trial["endT"] + POST_ROLL_SECONDS
			window_samples = slice_window(samples, start, end)
			window_events = slice_window(trace_events, start, end)
			handle.write(json.dumps({
				"label": trial["label"],
				"trial": index,
				"goT": trial["goT"],
				"endT": trial["endT"],
				"windowSeconds": trial["windowSeconds"],
				"expect": trial["expect"],
				"predicted": trial.get("predicted"),
				"samples": [
					[s["t"], s["ct"], s["x"], s["y"], s["z"], s.get("px", 0.0), s.get("py", 0.0)]
					for s in window_samples
				],
				"events": [
					{"t": e["t"], "name": e.get("name"), "detail": e.get("detail")}
					for e in window_events
				],
			}, separators=(",", ":")) + "\n")
	print(f"\nExported {len(trials)} labeled trials → {export_path}")


def main():
	parser = argparse.ArgumentParser(description="Analyze a gesture-labeling capture against the app motion trace.")
	parser.add_argument("capture_dir", nargs="?", type=Path,
		help="Capture dir from serve.py (default: latest under captures/)")
	parser.add_argument("--trace", type=Path, default=DEFAULT_TRACE,
		help=f"App motion trace ndjson (default: {DEFAULT_TRACE})")
	parser.add_argument("--export", type=Path,
		help="Dataset output path (default: <capture>/gesture-dataset.ndjson)")
	args = parser.parse_args()

	capture_dir = args.capture_dir or latest_capture_dir(DEFAULT_CAPTURE_ROOT)
	session_events = latest_gesture_session(load_events(capture_dir))
	trials = build_trials(session_events)
	if not trials:
		raise SystemExit("Session contains no completed trials.")

	session_start = trials[0]["goT"]
	session_end = trials[-1]["endT"]
	samples, trace_events = load_trace(args.trace, session_start, session_end)

	# A prompted window with no trace samples is lost data (trace not yet
	# enabled, app restarted, …), not a recognition miss — flag and exclude it
	# so the confusion matrix only scores trials the recognizers could see.
	covered, dropped = [], []
	for trial in trials:
		window = slice_window(samples, trial["goT"] - PRE_ROLL_SECONDS, trial["endT"] + POST_ROLL_SECONDS)
		(covered if window else dropped).append(trial)
	if dropped:
		by_class = Counter(trial["label"] for trial in dropped)
		print(f"⚠ {len(dropped)}/{len(trials)} trial windows have NO trace samples — excluded from scoring "
			f"({', '.join(f'{k}×{v}' for k, v in sorted(by_class.items()))}). "
			"Check when the trace flag was enabled relative to session start.")
	trials = covered

	print(f"Capture: {capture_dir}")
	print(f"Trace:   {args.trace}")
	print(f"Trials:  {len(trials)} with trace coverage "
		f"({session_end - session_start:.0f}s span, {len(samples)} trace samples, {len(trace_events)} trace events)")
	if not samples:
		print("⚠ Trace has NO samples inside the session window. Enable the flag and restart the app:\n"
			"  defaults write KevinTang.XboxControllerMapper ouraMotionTraceLogging -bool true")

	per_class = Counter(trial["label"] for trial in trials)
	print("  Per class: " + ", ".join(f"{label}×{count}" for label, count in sorted(per_class.items())))

	report_sample_rate(samples)
	report_confusion(trials, trace_events)

	export_path = args.export or (capture_dir / "gesture-dataset.ndjson")
	export_dataset(trials, samples, trace_events, export_path)


if __name__ == "__main__":
	main()
