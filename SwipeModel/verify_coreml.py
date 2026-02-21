"""Verify Core ML model produces same output as PyTorch model."""
import numpy as np
import torch
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from model import SwipeTransformer
from dataset import MAX_WORD_LEN, SOS_TOKEN, PAD_TOKEN, MAX_STROKE_LEN, VOCAB_SIZE
from keyboard_layout import LAYOUT, key_proximity, nearest_key, ALPHABET, LETTER_TO_IDX

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

# Create a simple test: swipe for "hello" - go through h, e, l, l, o key positions
key_centers = {k.lower(): v for k, v in LAYOUT.items()}
hello_keys = ['h', 'e', 'l', 'l', 'o']
samples_per_key = 8
total_samples = len(hello_keys) * samples_per_key

# Build feature tensor
features_np = np.zeros((1, MAX_STROKE_LEN, 29), dtype=np.float32)
for ki, key in enumerate(hello_keys):
    cx, cy = key_centers[key]
    for si in range(samples_per_key):
        idx = ki * samples_per_key + si
        if idx >= MAX_STROKE_LEN:
            break
        # Interpolate between keys
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
        features_np[0, idx, 2] = 0.02  # dt
        prox = key_proximity(x, y)
        features_np[0, idx, 3:29] = prox

stroke_len_np = np.array([total_samples], dtype=np.int64)
target_len = MAX_WORD_LEN + 2

print(f"Test: 'hello' swipe, {total_samples} samples")
print(f"First 3 feature samples:")
for i in range(3):
    print(f"  [{i}] x={features_np[0,i,0]:.3f} y={features_np[0,i,1]:.3f} dt={features_np[0,i,2]:.3f} prox_top3={sorted(enumerate(features_np[0,i,3:29]), key=lambda x:-x[1])[:3]}")

# PyTorch beam search
print("\n--- PyTorch Model ---")
features_t = torch.from_numpy(features_np)
stroke_len_t = torch.from_numpy(stroke_len_np)

with torch.no_grad():
    batch_results = model.predict(features_t, stroke_len_t, beam_width=3, max_len=MAX_WORD_LEN+1)
    beam_results = batch_results[0]  # First (only) batch item
    for tokens, score in beam_results[:5]:
        word = ''.join(chr(ord('a')+t-1) for t in tokens if 1<=t<=26)
        print(f"  '{word}' (score={score:.3f}, tokens={tokens})")

# Also test one-step logits to verify
target_tokens = torch.full((1, target_len), PAD_TOKEN, dtype=torch.long)
target_tokens[0, 0] = SOS_TOKEN
with torch.no_grad():
    logits = model(features_t, stroke_len_t, target_tokens)
    # First position logits (predicting first character after SOS)
    first_logits = logits[0, 0, :]  # (VOCAB_SIZE,)
    probs = torch.softmax(first_logits, dim=-1)
    top5 = torch.topk(probs, 5)
    print(f"\nFirst token predictions (after SOS):")
    for i in range(5):
        token = top5.indices[i].item()
        prob = top5.values[i].item()
        if 1 <= token <= 26:
            char = chr(ord('a') + token - 1)
        elif token == 0:
            char = '<PAD>'
        elif token == 27:
            char = '<SOS>'
        elif token == 28:
            char = '<EOS>'
        else:
            char = f'<{token}>'
        print(f"  token={token} ({char}) prob={prob:.4f}")

# Now test Core ML
print("\n--- Core ML Model ---")
try:
    import coremltools as ct
    cml_model = ct.models.MLModel("exported/SwipeTyping.mlpackage")

    # Test with same input
    cml_out = cml_model.predict({
        "features": features_np,
        "stroke_len": stroke_len_np.astype(np.int32),
        "target_tokens": target_tokens.numpy().astype(np.int32),
    })
    cml_logits = cml_out["logits"]
    print(f"Core ML logits shape: {cml_logits.shape}")

    # Compare first position logits
    cml_first = cml_logits[0, 0, :]
    pt_first = first_logits.numpy()

    diff = np.abs(cml_first - pt_first)
    print(f"Max logit diff (position 0): {diff.max():.6f}")
    print(f"Mean logit diff: {diff.mean():.6f}")

    cml_probs = np.exp(cml_first) / np.exp(cml_first).sum()
    cml_top5_idx = np.argsort(-cml_probs)[:5]
    print(f"\nCore ML first token predictions:")
    for idx in cml_top5_idx:
        if 1 <= idx <= 26:
            char = chr(ord('a') + idx - 1)
        elif idx == 0:
            char = '<PAD>'
        elif idx == 27:
            char = '<SOS>'
        elif idx == 28:
            char = '<EOS>'
        else:
            char = f'<{idx}>'
        print(f"  token={idx} ({char}) prob={cml_probs[idx]:.4f}")

    # Also try with int64 stroke_len (matching trace dtype)
    print("\n--- Core ML with int64 stroke_len ---")
    cml_out2 = cml_model.predict({
        "features": features_np,
        "stroke_len": stroke_len_np,  # int64
        "target_tokens": target_tokens.numpy().astype(np.int32),
    })
    cml_logits2 = cml_out2["logits"]
    diff2 = np.abs(cml_logits2[0, 0, :] - pt_first)
    print(f"Max logit diff (int64 stroke_len): {diff2.max():.6f}")

except Exception as e:
    print(f"Core ML test failed: {e}")
    import traceback
    traceback.print_exc()
