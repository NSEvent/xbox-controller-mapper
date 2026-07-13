#!/usr/bin/env python3
"""End-to-end evaluation of the full Oura gesture pipeline on every labeled
session — the single command that answers "how well does it work":

  python3 evaluate.py                # all sessions, canonical pipeline
  python3 evaluate.py --checkpoint checkpoints/candidate.pt

Replays the exact production pipeline (impulse detection, classification with
tap-lean + heuristic corroboration, sequence counting, hold, flick gates,
cooldowns) sample-by-sample over each session's archived motion trace and
scores against the prompted labels. Exits non-zero if any session scores
below --min-accuracy (default 90%).
"""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent / "Tools" / "oura-calibration"))

import torch
from dataclasses import replace

from model import OuraGestureNet
from replay_ml import MLPipeline
from tune_gestures import (Params, SHIPPED_2026_07_06, load_trace, score,
	print_confusion, build_trials, latest_gesture_session, load_events,
	split_by_coverage)

CAPTURES = ROOT.parent / "Tools" / "oura-calibration" / "captures"


def evaluate(model, capture, verbose=True):
	samples, _, centers = load_trace(capture / "motion-trace.ndjson")
	trials, dropped = split_by_coverage(
		build_trials(latest_gesture_session(load_events(capture))), samples)
	ct_offset = sum(s[6] - s[0] for s in samples[:200]) / 200
	pipe = MLPipeline(model, replace(Params(), **SHIPPED_2026_07_06))
	ci = 0
	for s in samples:
		while ci < len(centers) and centers[ci] <= s[0]:
			pipe.feed_center(centers[ci]); ci += 1
		pipe.fire_due_timers(s[0])
		pipe.feed_sample(s[6], s[0], s[1], s[2], s[3], s[4], s[5])
	pipe.fire_due_timers(samples[-1][0] + 5)
	correct, clean, rows = score(trials, pipe.events, ct_offset)
	if verbose:
		print(f"\n=== {capture.name}: {correct}/{len(trials)} "
			f"({100 * correct / len(trials):.0f}%) noise-clean={clean} ===")
		print_confusion(rows, correct, len(trials))
	return correct, len(trials), clean


def main():
	parser = argparse.ArgumentParser(description="End-to-end pipeline evaluation over all labeled sessions.")
	parser.add_argument("--checkpoint", type=Path, default=ROOT / "checkpoints" / "oura_gesture.pt")
	parser.add_argument("--min-accuracy", type=float, default=0.90)
	args = parser.parse_args()

	checkpoint = torch.load(args.checkpoint, weights_only=True)
	model = OuraGestureNet()
	model.load_state_dict(checkpoint["state_dict"])
	model.eval()

	sessions = sorted(p for p in CAPTURES.iterdir()
		if (p / "motion-trace.ndjson").exists() and (p / "gesture-dataset.ndjson").exists())
	if not sessions:
		raise SystemExit("no labeled sessions with archived traces found")

	failures = 0
	for capture in sessions:
		correct, total, clean = evaluate(model, capture)
		if correct / total < args.min_accuracy or not clean:
			failures += 1
	print(f"\n{len(sessions)} sessions evaluated, {failures} below the {args.min_accuracy:.0%} bar")
	sys.exit(1 if failures else 0)


if __name__ == "__main__":
	main()
