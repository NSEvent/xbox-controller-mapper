"""Tiny 1D CNN over 32×5 motion windows → 6 gesture classes.

Input is RAW sensor values ([x, y, z] in g, [px, py] projected input) — the
per-channel normalization constants are baked into the module as buffers so
the Swift caller never needs to know them.
"""
import torch
import torch.nn as nn

CLASSES = ["tap", "flick-up", "flick-down", "flick-left", "flick-right", "noise"]
WINDOW_STEPS = 32
CHANNELS = 5


class OuraGestureNet(nn.Module):
	def __init__(self, mean=None, std=None):
		super().__init__()
		self.register_buffer("input_mean", torch.zeros(CHANNELS) if mean is None else torch.as_tensor(mean, dtype=torch.float32))
		self.register_buffer("input_std", torch.ones(CHANNELS) if std is None else torch.as_tensor(std, dtype=torch.float32))
		self.features = nn.Sequential(
			nn.Conv1d(CHANNELS, 32, kernel_size=5, padding=2),
			nn.ReLU(),
			nn.MaxPool1d(2),
			nn.Conv1d(32, 64, kernel_size=3, padding=1),
			nn.ReLU(),
			nn.MaxPool1d(2),
			nn.Conv1d(64, 64, kernel_size=3, padding=1),
			nn.ReLU(),
		)
		self.head = nn.Linear(64, len(CLASSES))

	def forward(self, x):
		# x: (B, 32, 5) raw → normalize → (B, 5, 32)
		x = (x - self.input_mean) / self.input_std
		x = x.permute(0, 2, 1)
		x = self.features(x)
		x = x.mean(dim=2)
		return self.head(x)
