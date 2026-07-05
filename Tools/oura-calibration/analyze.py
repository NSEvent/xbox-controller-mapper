#!/usr/bin/env python3
import argparse
import json
import math
import re
from datetime import datetime, timezone
from pathlib import Path


LOG_PATTERN = re.compile(
	r"^(?P<iso>\S+) motion raw "
	r"(?P<rawx>-?\d+(?:\.\d+)?) (?P<rawy>-?\d+(?:\.\d+)?) (?P<rawz>-?\d+(?:\.\d+)?) "
	r"centered (?P<centerx>-?\d+(?:\.\d+)?) (?P<centery>-?\d+(?:\.\d+)?) (?P<centerz>-?\d+(?:\.\d+)?) "
	r"input (?P<inputx>-?\d+(?:\.\d+)?) (?P<inputy>-?\d+(?:\.\d+)?) "
	r"stick (?P<stickx>-?\d+(?:\.\d+)?) (?P<sticky>-?\d+(?:\.\d+)?)"
)


def parse_iso_seconds(value):
	if value.endswith("Z"):
		value = value[:-1] + "+00:00"
	return datetime.fromisoformat(value).timestamp()


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


def latest_session_events(events):
	start_index = None
	for index, event in enumerate(events):
		if event.get("type") == "session:start":
			start_index = index
	if start_index is None:
		return events

	for end_index in range(start_index + 1, len(events)):
		if events[end_index].get("type") == "session:end":
			return events[start_index:end_index + 1]
	return events[start_index:]


def build_windows(events):
	starts = {}
	windows = []
	for event in events:
		event_type = event.get("type")
		if event_type == "target:start":
			starts[event["trialIndex"]] = event
		elif event_type == "target:end":
			start = starts.get(event["trialIndex"])
			if not start:
				continue
			target = start["target"]
			windows.append({
				"trialIndex": start["trialIndex"],
				"target": target,
				"start": event_seconds(start),
				"end": event_seconds(event),
			})
	return windows


def parse_log(log_path, start_time, end_time):
	samples = []
	if not log_path.exists():
		raise SystemExit(f"Missing Oura log: {log_path}")
	for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
		match = LOG_PATTERN.match(line)
		if not match:
			continue
		timestamp = parse_iso_seconds(match.group("iso"))
		if timestamp < start_time or timestamp > end_time:
			continue
		value = {key: float(match.group(key)) for key in match.groupdict() if key != "iso"}
		samples.append({
			"timestamp": timestamp,
			"raw": (value["rawx"], value["rawy"], value["rawz"]),
			"centered": (value["centerx"], value["centery"], value["centerz"]),
			"input": (value["inputx"], value["inputy"]),
			"stick": (value["stickx"], value["sticky"]),
		})
	return samples


def mean(values):
	values = list(values)
	return sum(values) / len(values) if values else 0.0


def stdev(values):
	if len(values) < 2:
		return 0.0
	avg = mean(values)
	return math.sqrt(sum((value - avg) ** 2 for value in values) / (len(values) - 1))


def vector_mean(samples, key):
	size = len(samples[0][key])
	return tuple(mean(sample[key][index] for sample in samples) for index in range(size))


def vector_stdev(samples, key):
	size = len(samples[0][key])
	return tuple(stdev([sample[key][index] for sample in samples]) for index in range(size))


def select_samples(samples, window, trim_start, trim_end):
	start = window["start"] + trim_start
	end = max(start, window["end"] - trim_end)
	return [sample for sample in samples if start <= sample["timestamp"] <= end]


def solve_linear_system(matrix, vector):
	n = len(vector)
	a = [row[:] + [vector[index]] for index, row in enumerate(matrix)]
	for column in range(n):
		pivot = max(range(column, n), key=lambda row: abs(a[row][column]))
		if abs(a[pivot][column]) < 1e-12:
			raise ValueError("singular matrix")
		a[column], a[pivot] = a[pivot], a[column]
		scale = a[column][column]
		a[column] = [value / scale for value in a[column]]
		for row in range(n):
			if row == column:
				continue
			factor = a[row][column]
			a[row] = [a[row][col] - factor * a[column][col] for col in range(n + 1)]
	return [a[row][n] for row in range(n)]


def least_squares(rows, values, ridge=1e-5):
	width = len(rows[0])
	ata = [[0.0 for _ in range(width)] for _ in range(width)]
	atb = [0.0 for _ in range(width)]
	for row, value in zip(rows, values):
		for i in range(width):
			atb[i] += row[i] * value
			for j in range(width):
				ata[i][j] += row[i] * row[j]
	for i in range(width):
		ata[i][i] += ridge
	return solve_linear_system(ata, atb)


def correlation(xs, ys):
	if len(xs) < 2:
		return 0.0
	x_mean = mean(xs)
	y_mean = mean(ys)
	numerator = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys))
	denominator = math.sqrt(
		sum((x - x_mean) ** 2 for x in xs) *
		sum((y - y_mean) ** 2 for y in ys)
	)
	return numerator / denominator if denominator else 0.0


def format_vec(values):
	return " ".join(f"{value:+.3f}" for value in values)


def format_model(coefficients, names):
	return " ".join(f"{coef:+.3f}*{name}" for coef, name in zip(coefficients, names))


def analyze(capture_dir, log_path, trim_start, trim_end, all_sessions):
	events = load_events(capture_dir)
	if not all_sessions:
		events = latest_session_events(events)
	windows = build_windows(events)
	if not windows:
		raise SystemExit("No target windows recorded. Start and complete a calibration pass first.")
	start_time = min(window["start"] for window in windows) - 2
	end_time = max(window["end"] for window in windows) + 2
	samples = parse_log(log_path, start_time, end_time)
	if not samples:
		raise SystemExit("No Oura motion samples found in the calibration window.")

	rows_by_trial = []
	for window in windows:
		window_samples = select_samples(samples, window, trim_start, trim_end)
		if not window_samples:
			continue
		row = {
			"trialIndex": window["trialIndex"],
			"target": window["target"],
			"count": len(window_samples),
			"raw": vector_mean(window_samples, "raw"),
			"rawStd": vector_stdev(window_samples, "raw"),
			"centered": vector_mean(window_samples, "centered"),
			"input": vector_mean(window_samples, "input"),
			"stick": vector_mean(window_samples, "stick"),
		}
		rows_by_trial.append(row)

	print(f"Capture: {capture_dir}")
	print(f"Oura log: {log_path}")
	print(f"Samples: {len(samples)} total, {sum(row['count'] for row in rows_by_trial)} in trimmed hold windows")
	print("")
	print("Per target means")
	print("target          n  targetXY       raw mean          centered mean     input mean   stick mean")
	for row in rows_by_trial:
		target = row["target"]
		print(
			f"{target['label'][:13]:13} "
			f"{row['count']:3d} "
			f"{target['x']:+.2f},{target['y']:+.2f}  "
			f"{format_vec(row['raw'])}  "
			f"{format_vec(row['centered'])}  "
			f"{format_vec(row['input'])}  "
			f"{format_vec(row['stick'])}"
		)

	if len(rows_by_trial) < 5:
		print("\nNeed at least 5 target windows for regression.")
		return

	print("")
	print("Raw-axis correlation with intended screen direction")
	for key, names in (("raw", ("raw.x", "raw.y", "raw.z")), ("centered", ("center.x", "center.y", "center.z")), ("input", ("input.x", "input.y"))):
		for target_axis, label in ((0, "screenX"), (1, "screenY")):
			target_values = [row["target"]["x" if target_axis == 0 else "y"] for row in rows_by_trial]
			values = [correlation([row[key][index] for row in rows_by_trial], target_values) for index in range(len(rows_by_trial[0][key]))]
			print(f"{key:8} -> {label}: " + " ".join(f"{name}={value:+.3f}" for name, value in zip(names, values)))

	print("")
	print("Least-squares projection from ring vectors to intended target")
	for key, names in (("raw", ("raw.x", "raw.y", "raw.z", "bias")), ("centered", ("center.x", "center.y", "center.z", "bias")), ("input", ("input.x", "input.y", "bias"))):
		rows = [list(row[key]) + [1.0] for row in rows_by_trial]
		target_x = [row["target"]["x"] for row in rows_by_trial]
		target_y = [row["target"]["y"] for row in rows_by_trial]
		try:
			model_x = least_squares(rows, target_x)
			model_y = least_squares(rows, target_y)
		except ValueError:
			print(f"{key}: singular fit")
			continue
		print(f"{key:8} screenX = {format_model(model_x, names)}")
		print(f"{key:8} screenY = {format_model(model_y, names)}")


def main():
	parser = argparse.ArgumentParser(description="Analyze an Oura calibration capture against ControllerKeys-Oura.log.")
	parser.add_argument("capture_dir", nargs="?", type=Path, help="Capture directory from serve.py. Defaults to latest capture.")
	parser.add_argument("--capture-root", type=Path, default=Path(__file__).resolve().parent / "captures")
	parser.add_argument("--log", type=Path, default=Path.home() / "Library/Logs/ControllerKeys-Oura.log")
	parser.add_argument("--trim-start", type=float, default=0.55, help="Seconds to ignore after each target appears.")
	parser.add_argument("--trim-end", type=float, default=0.15, help="Seconds to ignore before each target ends.")
	parser.add_argument("--all-sessions", action="store_true", help="Analyze every session in the capture file.")
	args = parser.parse_args()

	capture_dir = args.capture_dir.expanduser() if args.capture_dir else latest_capture_dir(args.capture_root.expanduser())
	analyze(capture_dir, args.log.expanduser(), args.trim_start, args.trim_end, args.all_sessions)


if __name__ == "__main__":
	main()
