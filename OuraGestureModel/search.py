#!/usr/bin/env python3
"""Overnight model search: architecture / window / augmentation / schedule.

For each config: rebuild per-event windows at the config's span, run grouped
8-fold CV, log to search-results.json. Top configs by CV then get the real
test — full-pipeline replay on both labeled sessions (with pipeline window
constants matched). Writes the final ranking and leaves the best checkpoint
at checkpoints/candidate.pt (canonical oura_gesture.pt is NOT touched).
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent / "Tools" / "oura-calibration"))

import numpy as np
import torch
import torch.nn as nn
from dataclasses import replace

import build_dataset
import model as model_mod
import train as train_mod
import replay_ml
from tune_gestures import (Params, SHIPPED_2026_07_06, load_trace, score,
	build_trials, latest_gesture_session, load_events, split_by_coverage)

CAPTURES = ROOT.parent / "Tools" / "oura-calibration" / "captures"
SESSIONS = ["20260705-231028", "20260706-013512"]
RESULTS = ROOT / "search-results.json"

CONFIGS = [
	{"name": "baseline",              "post": 0.38, "ch": (24, 48, 48), "epochs": 160, "noise": 0.02, "shift": 4},
	{"name": "post30",                "post": 0.30, "ch": (24, 48, 48), "epochs": 160, "noise": 0.02, "shift": 4},
	{"name": "post24",                "post": 0.24, "ch": (24, 48, 48), "epochs": 160, "noise": 0.02, "shift": 4},
	{"name": "wide",                  "post": 0.38, "ch": (32, 64, 64), "epochs": 160, "noise": 0.02, "shift": 4},
	{"name": "long",                  "post": 0.38, "ch": (24, 48, 48), "epochs": 320, "noise": 0.02, "shift": 4},
	{"name": "aug",                   "post": 0.38, "ch": (24, 48, 48), "epochs": 160, "noise": 0.04, "shift": 6},
	{"name": "wide-long-aug",         "post": 0.38, "ch": (32, 64, 64), "epochs": 320, "noise": 0.04, "shift": 6},
	{"name": "post30-wide-long",      "post": 0.30, "ch": (32, 64, 64), "epochs": 320, "noise": 0.02, "shift": 4},
	{"name": "post24-wide-long-aug",  "post": 0.24, "ch": (32, 64, 64), "epochs": 320, "noise": 0.04, "shift": 6},
]


def make_net_class(channels):
	c1, c2, c3 = channels

	class Net(nn.Module):
		def __init__(self, mean=None, std=None):
			super().__init__()
			self.register_buffer("input_mean", torch.zeros(5) if mean is None else torch.as_tensor(mean, dtype=torch.float32))
			self.register_buffer("input_std", torch.ones(5) if std is None else torch.as_tensor(std, dtype=torch.float32))
			self.features = nn.Sequential(
				nn.Conv1d(5, c1, 5, padding=2), nn.ReLU(), nn.MaxPool1d(2),
				nn.Conv1d(c1, c2, 3, padding=1), nn.ReLU(), nn.MaxPool1d(2),
				nn.Conv1d(c2, c3, 3, padding=1), nn.ReLU(),
			)
			self.head = nn.Linear(c3, len(model_mod.CLASSES))

		def forward(self, x):
			x = (x - self.input_mean) / self.input_std
			x = x.permute(0, 2, 1)
			return self.head(self.features(x).mean(dim=2))
	return Net


def build_events(post):
	build_dataset.WINDOW_POST = post
	events = []
	for i, name in enumerate(SESSIONS):
		cap = CAPTURES / name
		trials = [json.loads(l) for l in (cap / "gesture-dataset.ndjson").read_text().splitlines() if l.strip()]
		covered = [t for t in trials if t["samples"]]
		for index, trial in enumerate(covered):
			for e in build_dataset.events_from_trial(trial, index):
				e["group"] = f"s{i}-{e['group']}"
				events.append(e)
		first = covered[0]["samples"][0]
		for e in build_dataset.rest_phase_events(cap / "motion-trace.ndjson", covered, first[0] - first[1]):
			e["group"] = f"s{i}-{e['group']}"
			events.append(e)
	return events


def patched_train(events, net_class, epochs, noise, shift, seed):
	import random
	torch.manual_seed(seed); random.seed(seed); np.random.seed(seed)
	mean, std = train_mod.norm_stats(events)
	net = net_class(mean, std)
	ds = train_mod.EventDataset(events, augment=True)

	orig_getitem = train_mod.EventDataset.__getitem__
	def getitem(self, i):
		w = self.windows[i]
		s = random.randint(-shift, shift)
		if s:
			w = np.roll(w, s, axis=0)
			if s > 0: w[:s] = w[s]
			else: w[s:] = w[s - 1]
		w = w * random.uniform(0.85, 1.15) + np.random.normal(0, noise, w.shape).astype(np.float32)
		return torch.from_numpy(w.astype(np.float32)), self.labels[i]
	train_mod.EventDataset.__getitem__ = getitem
	try:
		from torch.utils.data import DataLoader
		loader = DataLoader(ds, batch_size=32, shuffle=True)
		criterion = nn.CrossEntropyLoss(weight=train_mod.class_weights(events))
		opt = torch.optim.Adam(net.parameters(), lr=1e-3)
		sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)
		net.train()
		for _ in range(epochs):
			for x, y in loader:
				opt.zero_grad()
				criterion(net(x), y).backward()
				opt.step()
			sched.step()
	finally:
		train_mod.EventDataset.__getitem__ = orig_getitem
	return net


def grouped_cv(events, net_class, cfg):
	folds = train_mod.grouped_folds(events, 8)
	hits = total = 0
	for i, test in enumerate(folds):
		train_set = [e for j, f in enumerate(folds) if j != i for e in f]
		net = patched_train(train_set, net_class, cfg["epochs"], cfg["noise"], cfg["shift"], seed=7 + i)
		preds = train_mod.predict(net, test)
		hits += sum(1 for e, p in zip(test, preds) if model_mod.CLASSES[p] == e["label"])
		total += len(test)
	return hits, total


def replay_eval(net, post):
	build_dataset.WINDOW_POST = post
	replay_ml.WINDOW_POST = post
	results = []
	for name in SESSIONS:
		cap = CAPTURES / name
		samples, _, centers = load_trace(cap / "motion-trace.ndjson")
		trials, _ = split_by_coverage(build_trials(latest_gesture_session(load_events(cap))), samples)
		ct_offset = sum(s[6] - s[0] for s in samples[:200]) / 200
		pipe = replay_ml.MLPipeline(net, replace(Params(), **SHIPPED_2026_07_06))
		ci = 0
		for s in samples:
			while ci < len(centers) and centers[ci] <= s[0]:
				pipe.feed_center(centers[ci]); ci += 1
			pipe.fire_due_timers(s[0])
			pipe.feed_sample(s[6], s[0], s[1], s[2], s[3], s[4], s[5])
		pipe.fire_due_timers(samples[-1][0] + 5)
		correct, clean, _ = score(trials, pipe.events, ct_offset)
		results.append((correct, len(trials), clean))
	return results


def log(entry):
	rows = json.loads(RESULTS.read_text()) if RESULTS.exists() else []
	rows.append(entry)
	RESULTS.write_text(json.dumps(rows, indent=1))
	print(json.dumps(entry), flush=True)


def main():
	cv_scores = {}
	for cfg in CONFIGS:
		events = build_events(cfg["post"])
		net_class = make_net_class(cfg["ch"])
		hits, total = grouped_cv(events, net_class, cfg)
		cv_scores[cfg["name"]] = hits / total
		log({"stage": "cv", "config": cfg["name"], "cv": f"{hits}/{total}", "acc": round(hits / total, 4)})

	top = sorted(CONFIGS, key=lambda c: -cv_scores[c["name"]])[:4]
	best = None
	for cfg in top:
		events = build_events(cfg["post"])
		net = patched_train(events, make_net_class(cfg["ch"]), cfg["epochs"], cfg["noise"], cfg["shift"], seed=7)
		results = replay_eval(net, cfg["post"])
		total_correct = sum(r[0] for r in results)
		all_clean = all(r[2] for r in results)
		log({"stage": "replay", "config": cfg["name"],
			"sessions": [f"{c}/{n}" for c, n, _ in results], "clean": all_clean,
			"total": total_correct})
		if all_clean and (best is None or total_correct > best[0]):
			best = (total_correct, cfg, net)

	if best:
		total_correct, cfg, net = best
		torch.save({"state_dict": net.state_dict(), "classes": model_mod.CLASSES,
			"config": {k: v for k, v in cfg.items() if k != "ch"} | {"ch": list(cfg["ch"])}},
			ROOT / "checkpoints" / "candidate.pt")
		log({"stage": "winner", "config": cfg["name"], "total": total_correct})


if __name__ == "__main__":
	main()
