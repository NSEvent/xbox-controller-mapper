#!/usr/bin/env python3
"""Parity check: Core ML export vs the PyTorch checkpoint on real events."""
import json
import sys

import numpy as np
import torch
import coremltools as ct

from model import CLASSES, OuraGestureNet
from train import CHECKPOINT_DIR, DEFAULT_EVENTS
from export import EXPORT_DIR


def main():
	events_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_EVENTS
	events = [json.loads(l) for l in open(events_path) if l.strip()]

	checkpoint = torch.load(CHECKPOINT_DIR / "oura_gesture.pt", weights_only=True)
	model = OuraGestureNet()
	model.load_state_dict(checkpoint["state_dict"])
	model.eval()

	mlmodel = ct.models.MLModel(str(EXPORT_DIR / "OuraGestureClassifier.mlpackage"))

	max_diff = 0.0
	mismatches = 0
	for e in events:
		x = np.array([e["window"]], dtype=np.float32)
		with torch.no_grad():
			torch_logits = model(torch.from_numpy(x)).numpy()[0]
		coreml_logits = np.array(mlmodel.predict({"window": x})["logits"][0])
		max_diff = max(max_diff, float(np.abs(torch_logits - coreml_logits).max()))
		if torch_logits.argmax() != coreml_logits.argmax():
			mismatches += 1

	print(f"{len(events)} events: argmax mismatches {mismatches}, max |logit diff| {max_diff:.5f}")
	if mismatches or max_diff > 1e-3:
		raise SystemExit("PARITY FAILURE")
	print("parity OK")


if __name__ == "__main__":
	main()
