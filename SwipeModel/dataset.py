"""
Dataset loader for FUTO keyboard swipe data.

Loads the FUTO Keyboard dataset from HuggingFace (MIT license), filters invalid
rows, and re-maps mobile keyboard coordinates to the ControllerKeys layout.

Strategy: Each touch point is mapped to its nearest key on a standard mobile
QWERTY layout, then re-projected to that key's center on our desktop layout.
"""

import math
import numpy as np
import torch
from torch.utils.data import Dataset

from keyboard_layout import LAYOUT, ALPHABET, LETTER_TO_IDX, nearest_key, key_proximity

# Standard mobile QWERTY layout (normalized 0-1 for a typical phone keyboard)
# 10 keys across, 3 rows. We approximate centers.
_MOBILE_ROWS = [
    {"keys": list("QWERTYUIOP"), "y": 0.167},
    {"keys": list("ASDFGHJKL"), "y": 0.5},
    {"keys": list("ZXCVBNM"), "y": 0.833},
]

_MOBILE_LAYOUT = {}
for row in _MOBILE_ROWS:
    n = len(row["keys"])
    # Center keys within row with small margins
    margin = 0.05
    span = 1.0 - 2 * margin
    for i, key in enumerate(row["keys"]):
        x = margin + (i + 0.5) * span / n
        _MOBILE_LAYOUT[key] = (x, row["y"])


def _nearest_mobile_key(x: float, y: float) -> str:
    """Find nearest key on the mobile layout."""
    best = "A"
    best_d = float("inf")
    for ch, (cx, cy) in _MOBILE_LAYOUT.items():
        d = (x - cx) ** 2 + (y - cy) ** 2
        if d < best_d:
            best_d = d
            best = ch
    return best


def remap_point(mx: float, my: float) -> tuple[float, float]:
    """Map a mobile coordinate to our desktop layout via nearest-key projection."""
    key = _nearest_mobile_key(mx, my)
    return LAYOUT[key]


# Special tokens
PAD_TOKEN = 0
SOS_TOKEN = 27  # After A-Z (1-26)
EOS_TOKEN = 28
VOCAB_SIZE = 29  # PAD + 26 letters + SOS + EOS

MAX_STROKE_LEN = 80
MAX_WORD_LEN = 20


class SwipeDataset(Dataset):
    """Dataset of swipe traces mapped to words."""

    def __init__(self, samples: list[dict], augment: bool = False):
        """
        Args:
            samples: List of dicts with keys 'points' (list of (x,y,dt)) and 'word' (str)
            augment: Whether to apply data augmentation
        """
        self.samples = samples
        self.augment = augment

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        sample = self.samples[idx]
        points = sample["points"]  # list of (x, y, dt)
        word = sample["word"].upper()

        # Truncate stroke
        if len(points) > MAX_STROKE_LEN:
            # Subsample evenly
            indices = np.linspace(0, len(points) - 1, MAX_STROKE_LEN, dtype=int)
            points = [points[i] for i in indices]

        stroke_len = len(points)

        # Build input features: x, y, dt, 26-dim proximity
        features = []
        for x, y, dt in points:
            prox = key_proximity(x, y)
            features.append([x, y, dt] + prox)

        # Pad to MAX_STROKE_LEN
        feat_dim = 3 + 26  # x, y, dt, proximity
        while len(features) < MAX_STROKE_LEN:
            features.append([0.0] * feat_dim)

        # Build target: SOS + char indices + EOS + PAD
        target = [SOS_TOKEN]
        for ch in word[:MAX_WORD_LEN]:
            if ch in LETTER_TO_IDX:
                target.append(LETTER_TO_IDX[ch] + 1)  # 1-indexed (0 = PAD)
        target.append(EOS_TOKEN)
        target_len = len(target)
        while len(target) < MAX_WORD_LEN + 2:  # +2 for SOS/EOS
            target.append(PAD_TOKEN)

        # Optional augmentation
        feat_array = np.array(features, dtype=np.float32)
        if self.augment:
            # Small random shift
            feat_array[:stroke_len, 0] += np.random.normal(0, 0.01, stroke_len)
            feat_array[:stroke_len, 1] += np.random.normal(0, 0.01, stroke_len)
            # Small time jitter
            feat_array[:stroke_len, 2] *= np.random.uniform(0.9, 1.1)

        return {
            "features": torch.tensor(feat_array, dtype=torch.float32),
            "stroke_len": torch.tensor(stroke_len, dtype=torch.long),
            "target": torch.tensor(target, dtype=torch.long),
            "target_len": torch.tensor(target_len, dtype=torch.long),
        }


def load_futo_dataset(max_samples: int = None, split: str = "train") -> list[dict]:
    """
    Load the FUTO keyboard swipe dataset from HuggingFace.

    Dataset: futo-org/swipe.futo.org
    Schema: word (str), data (list of {t: int, x: float 0-1, y: float 0-1})

    Returns list of dicts with 'points' (remapped to our layout) and 'word'.
    """
    from datasets import load_dataset

    print("Loading FUTO swipe dataset from HuggingFace...")
    ds = load_dataset("futo-org/swipe.futo.org", split=split)

    samples = []
    skipped = 0

    for row in ds:
        word = row.get("word", "")
        touch_data = row.get("data", [])

        # Filter invalid
        if not word or not touch_data or len(touch_data) < 2:
            skipped += 1
            continue

        # Only keep alphabetic words
        if not word.isalpha() or len(word) > MAX_WORD_LEN:
            skipped += 1
            continue

        # Extract coordinates and timestamps from nested data
        # Each element is {"t": int_ms, "x": float_0_1, "y": float_0_1}
        xs = []
        ys = []
        ts = []
        valid = True
        for pt in touch_data:
            x = pt.get("x")
            y = pt.get("y")
            t = pt.get("t")
            if x is None or y is None:
                valid = False
                break
            xs.append(float(x))
            ys.append(float(y))
            ts.append(float(t) if t is not None else 0.0)

        if not valid:
            skipped += 1
            continue

        xs = np.array(xs, dtype=np.float64)
        ys = np.array(ys, dtype=np.float64)

        # Compute time deltas (timestamps are in milliseconds)
        ts_arr = np.array(ts, dtype=np.float64) / 1000.0  # Convert to seconds
        dts = np.diff(ts_arr, prepend=ts_arr[0])
        dts = np.clip(dts, 0, 1.0)

        # Remap each point from mobile to our layout
        points = []
        for x, y, dt in zip(xs, ys, dts):
            rx, ry = remap_point(float(x), float(y))
            points.append((rx, ry, float(dt)))

        samples.append({"points": points, "word": word})

        if max_samples and len(samples) >= max_samples:
            break

    print(f"Loaded {len(samples)} samples ({skipped} skipped)")
    return samples


if __name__ == "__main__":
    samples = load_futo_dataset(max_samples=100)
    if samples:
        s = samples[0]
        print(f"First sample: word='{s['word']}', points={len(s['points'])}")
        print(f"  First 3 points: {s['points'][:3]}")
