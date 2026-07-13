#!/usr/bin/env python3
"""Export the trained classifier to Core ML.

Produces exported/OuraGestureClassifier.mlpackage with a single input
"window" (1×32×5 float32 — raw [x,y,z,px,py] rows, normalization is baked in)
and output "logits" (1×6, class order model.CLASSES).

Copy the result into XboxControllerMapper/XboxControllerMapper/Resources/ —
the synchronized project group picks it up and coremlc compiles it into the
bundle (no pbxproj edit).
"""
import torch
import coremltools as ct

from model import CLASSES, WINDOW_STEPS, CHANNELS, OuraGestureNet
from train import CHECKPOINT_DIR

EXPORT_DIR = CHECKPOINT_DIR.parent / "exported"


def main():
	checkpoint = torch.load(CHECKPOINT_DIR / "oura_gesture.pt", weights_only=True)
	assert checkpoint["classes"] == CLASSES
	model = OuraGestureNet()
	model.load_state_dict(checkpoint["state_dict"])
	model.eval()

	example = torch.zeros(1, WINDOW_STEPS, CHANNELS)
	traced = torch.jit.trace(model, example)
	mlmodel = ct.convert(
		traced,
		inputs=[ct.TensorType(name="window", shape=example.shape, dtype=float)],
		outputs=[ct.TensorType(name="logits", dtype=float)],
		minimum_deployment_target=ct.target.macOS14,
		convert_to="mlprogram",
		# FP32: the model is ~5k params, and full precision keeps Core ML
		# bit-comparable to the PyTorch checkpoint for parity checks.
		compute_precision=ct.precision.FLOAT32,
	)
	mlmodel.short_description = (
		"Oura ring gesture event classifier (tap / 4 flick directions / noise) "
		f"over 32x5 raw motion windows; classes: {', '.join(CLASSES)}"
	)
	EXPORT_DIR.mkdir(exist_ok=True)
	out = EXPORT_DIR / "OuraGestureClassifier.mlpackage"
	mlmodel.save(str(out))
	print(f"saved → {out}")


if __name__ == "__main__":
	main()
