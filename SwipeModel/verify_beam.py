"""Verify beam search works correctly with Core ML model."""
import numpy as np
import torch
import sys, os
sys.path.insert(0, os.path.dirname(__file__))

from model import SwipeTransformer
from dataset import MAX_WORD_LEN, SOS_TOKEN, EOS_TOKEN, PAD_TOKEN, MAX_STROKE_LEN, VOCAB_SIZE
from keyboard_layout import LAYOUT, key_proximity

# Load PyTorch model
ckpt = torch.load("checkpoints/best_model.pt", map_location="cpu", weights_only=True)
config = ckpt.get("config", {})
model = SwipeTransformer(
    d_model=config.get("d_model", 128),
    n_heads=config.get("n_heads", 4),
    n_layers=config.get("n_layers", 3),
    input_dim=config.get("input_dim", 29),
)
model.load_state_dict(ckpt["model_state_dict"])
model.eval()

# Build "hello" features (same as before)
key_centers = {k.lower(): v for k, v in LAYOUT.items()}
hello_keys = ['h', 'e', 'l', 'l', 'o']
samples_per_key = 8
total_samples = len(hello_keys) * samples_per_key

features_np = np.zeros((1, MAX_STROKE_LEN, 29), dtype=np.float32)
np.random.seed(42)
for ki, key in enumerate(hello_keys):
    cx, cy = key_centers[key]
    for si in range(samples_per_key):
        idx = ki * samples_per_key + si
        if idx >= MAX_STROKE_LEN:
            break
        t = si / samples_per_key
        if ki + 1 < len(hello_keys):
            nx, ny = key_centers[hello_keys[ki + 1]]
            x = cx + t * (nx - cx) + np.random.normal(0, 0.01)
            y = cy + t * (ny - cy) + np.random.normal(0, 0.01)
        else:
            x = cx + np.random.normal(0, 0.01)
            y = cy + np.random.normal(0, 0.01)
        features_np[0, idx, 0] = x
        features_np[0, idx, 1] = y
        features_np[0, idx, 2] = 0.02
        prox = key_proximity(x, y)
        features_np[0, idx, 3:29] = prox

stroke_len_np = np.array([total_samples], dtype=np.int32)
target_len = MAX_WORD_LEN + 2  # 22

# Load Core ML model
import coremltools as ct
cml_model = ct.models.MLModel("exported/SwipeTyping.mlpackage")

# Manual greedy decode with Core ML (mimicking Swift beam search)
print("=== Greedy decode with Core ML (mimicking Swift) ===")
tokens = [SOS_TOKEN]
for step in range(MAX_WORD_LEN + 1):
    # Build target_tokens: pad to TARGET_LEN
    target_tokens = np.full((1, target_len), PAD_TOKEN, dtype=np.int32)
    for i, t in enumerate(tokens):
        if i < target_len:
            target_tokens[0, i] = t

    # Run model
    out = cml_model.predict({
        "features": features_np,
        "stroke_len": stroke_len_np,
        "target_tokens": target_tokens,
    })
    logits = out["logits"]  # (1, target_len-1, VOCAB_SIZE)

    # Get logits at position (len(tokens) - 1) — same as Swift
    logit_pos = len(tokens) - 1
    if logit_pos >= target_len - 1:
        break

    pos_logits = logits[0, logit_pos, :]  # (VOCAB_SIZE,)

    # Log-softmax
    max_val = pos_logits.max()
    log_probs = pos_logits - max_val - np.log(np.exp(pos_logits - max_val).sum())

    # Top 5
    top5_idx = np.argsort(-log_probs)[:5]

    def token_to_char(t):
        if 1 <= t <= 26: return chr(ord('a') + t - 1)
        if t == 0: return '<PAD>'
        if t == 27: return '<SOS>'
        if t == 28: return '<EOS>'
        return f'<{t}>'

    # Pick the best non-PAD token
    next_token = None
    for idx in top5_idx:
        if idx != PAD_TOKEN:
            next_token = idx
            break

    print(f"  step={step}, logit_pos={logit_pos}, top5: {[(token_to_char(i), f'{log_probs[i]:.3f}') for i in top5_idx]}")

    if next_token == EOS_TOKEN:
        tokens.append(int(next_token))
        break
    tokens.append(int(next_token))

word = ''.join(chr(ord('a') + t - 1) for t in tokens if 1 <= t <= 26)
print(f"\nCore ML greedy result: '{word}' (tokens={tokens})")

# Now compare: PyTorch one-step at each position
print("\n=== PyTorch step-by-step comparison ===")
features_t = torch.from_numpy(features_np)
stroke_len_t = torch.from_numpy(stroke_len_np.astype(np.int64))

tokens_pt = [SOS_TOKEN]
for step in range(MAX_WORD_LEN + 1):
    target_tokens_t = torch.full((1, target_len), PAD_TOKEN, dtype=torch.long)
    for i, t in enumerate(tokens_pt):
        if i < target_len:
            target_tokens_t[0, i] = t

    with torch.no_grad():
        logits_t = model(features_t, stroke_len_t, target_tokens_t)

    logit_pos = len(tokens_pt) - 1
    if logit_pos >= target_len - 1:
        break

    pos_logits_t = logits_t[0, logit_pos, :].numpy()
    max_val = pos_logits_t.max()
    log_probs_t = pos_logits_t - max_val - np.log(np.exp(pos_logits_t - max_val).sum())

    top5_idx = np.argsort(-log_probs_t)[:5]

    next_token = None
    for idx in top5_idx:
        if idx != PAD_TOKEN:
            next_token = idx
            break

    print(f"  step={step}, logit_pos={logit_pos}, top5: {[(token_to_char(i), f'{log_probs_t[i]:.3f}') for i in top5_idx]}")

    if next_token == EOS_TOKEN:
        tokens_pt.append(int(next_token))
        break
    tokens_pt.append(int(next_token))

word_pt = ''.join(chr(ord('a') + t - 1) for t in tokens_pt if 1 <= t <= 26)
print(f"\nPyTorch greedy result: '{word_pt}' (tokens={tokens_pt})")
