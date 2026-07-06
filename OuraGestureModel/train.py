#!/usr/bin/env python3
"""Train the Oura gesture classifier with honest grouped cross-validation.

Events from the same trial never straddle a train/test split (group = trial),
so CV numbers estimate performance on unseen gestures, not memorized windows.

  python3 train.py                      # 8-fold grouped CV, then final train on all data
  python3 train.py events_a.ndjson events_b.ndjson   # merge sessions
"""
import argparse
import json
import random
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset

from model import CLASSES, WINDOW_STEPS, OuraGestureNet

DEFAULT_EVENTS = Path(__file__).resolve().parent.parent / \
	"Tools/oura-calibration/captures/20260705-231028/events.ndjson"
CHECKPOINT_DIR = Path(__file__).resolve().parent / "checkpoints"

EPOCHS = 160
BATCH_SIZE = 32
LR = 1e-3
SEED = 7


class EventDataset(Dataset):
	def __init__(self, events, augment):
		self.windows = np.array([e["window"] for e in events], dtype=np.float32)
		self.labels = np.array([CLASSES.index(e["label"]) for e in events], dtype=np.int64)
		self.augment = augment

	def __len__(self):
		return len(self.labels)

	def __getitem__(self, i):
		w = self.windows[i]
		if self.augment:
			shift = random.randint(-4, 4)
			if shift:
				w = np.roll(w, shift, axis=0)
				if shift > 0:
					w[:shift] = w[shift]
				else:
					w[shift:] = w[shift - 1]
			w = w * random.uniform(0.85, 1.15)
			w = w + np.random.normal(0, 0.02, w.shape).astype(np.float32)
		return torch.from_numpy(w.astype(np.float32)), self.labels[i]


def load_events(paths):
	events = []
	for p, path in enumerate(paths):
		for line in Path(path).read_text().splitlines():
			if line.strip():
				e = json.loads(line)
				e["group"] = f"s{p}-{e['group']}"
				events.append(e)
	return events


def class_weights(events):
	counts = Counter(e["label"] for e in events)
	total = sum(counts.values())
	return torch.tensor([total / (len(CLASSES) * counts.get(c, 1)) for c in CLASSES], dtype=torch.float32)


def norm_stats(events):
	stacked = np.concatenate([np.array(e["window"], dtype=np.float32) for e in events])
	return stacked.mean(axis=0), stacked.std(axis=0) + 1e-6


def train_one(train_events, epochs=EPOCHS, seed=SEED):
	torch.manual_seed(seed)
	random.seed(seed)
	np.random.seed(seed)
	mean, std = norm_stats(train_events)
	model = OuraGestureNet(mean, std)
	loader = DataLoader(EventDataset(train_events, augment=True),
		batch_size=BATCH_SIZE, shuffle=True, drop_last=False)
	criterion = nn.CrossEntropyLoss(weight=class_weights(train_events))
	optimizer = torch.optim.Adam(model.parameters(), lr=LR)
	scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
	model.train()
	for _ in range(epochs):
		for x, y in loader:
			optimizer.zero_grad()
			loss = criterion(model(x), y)
			loss.backward()
			optimizer.step()
		scheduler.step()
	return model


@torch.no_grad()
def predict(model, events):
	model.eval()
	x = torch.tensor(np.array([e["window"] for e in events], dtype=np.float32))
	return model(x).argmax(dim=1).tolist()


def grouped_folds(events, k):
	groups = sorted({e["group"] for e in events})
	rng = random.Random(SEED)
	rng.shuffle(groups)
	assignment = {g: i % k for i, g in enumerate(groups)}
	folds = defaultdict(list)
	for e in events:
		folds[assignment[e["group"]]].append(e)
	return [folds[i] for i in range(k)]


def cross_validate(events, k):
	folds = grouped_folds(events, k)
	confusion = defaultdict(Counter)
	for i, test in enumerate(folds):
		train = [e for j, fold in enumerate(folds) if j != i for e in fold]
		model = train_one(train, epochs=EPOCHS, seed=SEED + i)
		for e, pred in zip(test, predict(model, test)):
			confusion[e["label"]][CLASSES[pred]] += 1
		hits = sum(confusion[c][c] for c in CLASSES)
		total = sum(sum(row.values()) for row in confusion.values())
		print(f"  fold {i + 1}/{k} done — running accuracy {hits}/{total}")
	return confusion


def print_confusion(confusion):
	width = max(len(c) for c in CLASSES) + 2
	total_hits = total = 0
	for label in CLASSES:
		row = confusion.get(label, Counter())
		n = sum(row.values())
		if n == 0:
			continue
		hits = row.get(label, 0)
		total_hits += hits
		total += n
		parts = ", ".join(f"{p}×{c}" for p, c in row.most_common())
		print(f"  {label:<{width}} {hits}/{n}   [{parts}]")
	if total:
		print(f"  Overall: {total_hits}/{total} ({100 * total_hits / total:.0f}%)")


def main():
	parser = argparse.ArgumentParser(description="Train the Oura gesture classifier.")
	parser.add_argument("events", nargs="*", default=[DEFAULT_EVENTS], type=Path)
	parser.add_argument("--folds", type=int, default=8)
	parser.add_argument("--skip-cv", action="store_true")
	args = parser.parse_args()

	events = load_events(args.events)
	print(f"{len(events)} events: " +
		", ".join(f"{l}×{c}" for l, c in sorted(Counter(e['label'] for e in events).items())))

	if not args.skip_cv:
		print(f"\n== {args.folds}-fold grouped CV ==")
		confusion = cross_validate(events, args.folds)
		print_confusion(confusion)

	print("\n== Final train on all events ==")
	model = train_one(events)
	CHECKPOINT_DIR.mkdir(exist_ok=True)
	out = CHECKPOINT_DIR / "oura_gesture.pt"
	torch.save({"state_dict": model.state_dict(), "classes": CLASSES}, out)
	train_preds = predict(model, events)
	hits = sum(1 for e, p in zip(events, train_preds) if CLASSES[p] == e["label"])
	print(f"train-set accuracy {hits}/{len(events)} (sanity, not a performance claim)")
	print(f"saved → {out}")


if __name__ == "__main__":
	main()
