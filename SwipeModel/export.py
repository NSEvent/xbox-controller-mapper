"""
Export trained PyTorch model to Core ML (.mlpackage).

Fully decomposes Transformer into basic ops (Linear, matmul, softmax,
LayerNorm) that coremltools supports — avoids fused _transformer_encoder_layer_fwd
and _native_multi_head_attention ops.
"""

import argparse
import os
import math

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from model import SwipeTransformer, MAX_STROKE_LEN, VOCAB_SIZE, PositionalEncoding
from dataset import MAX_WORD_LEN, SOS_TOKEN, PAD_TOKEN


class ManualMHA(nn.Module):
    """Multi-head attention using only basic ops."""

    def __init__(self, mha: nn.MultiheadAttention):
        super().__init__()
        d_model = mha.embed_dim
        n_heads = mha.num_heads
        self.n_heads = n_heads
        self.d_k = d_model // n_heads
        self.scale = 1.0 / math.sqrt(self.d_k)

        # nn.MultiheadAttention stores weights as in_proj_weight (3*d, d) and out_proj
        if mha.in_proj_weight is not None:
            # Fused QKV projection
            self.q_proj = nn.Linear(d_model, d_model, bias=mha.in_proj_bias is not None)
            self.k_proj = nn.Linear(d_model, d_model, bias=mha.in_proj_bias is not None)
            self.v_proj = nn.Linear(d_model, d_model, bias=mha.in_proj_bias is not None)
            # Split the fused weight
            w = mha.in_proj_weight.data
            self.q_proj.weight.data = w[:d_model]
            self.k_proj.weight.data = w[d_model:2*d_model]
            self.v_proj.weight.data = w[2*d_model:]
            if mha.in_proj_bias is not None:
                b = mha.in_proj_bias.data
                self.q_proj.bias.data = b[:d_model]
                self.k_proj.bias.data = b[d_model:2*d_model]
                self.v_proj.bias.data = b[2*d_model:]
        else:
            self.q_proj = nn.Linear(d_model, d_model)
            self.k_proj = nn.Linear(d_model, d_model)
            self.v_proj = nn.Linear(d_model, d_model)
            self.q_proj.weight.data = mha.q_proj_weight.data
            self.k_proj.weight.data = mha.k_proj_weight.data
            self.v_proj.weight.data = mha.v_proj_weight.data

        self.out_proj = nn.Linear(d_model, d_model)
        self.out_proj.weight.data = mha.out_proj.weight.data
        self.out_proj.bias.data = mha.out_proj.bias.data

    def forward(self, query, key, value, attn_mask=None, key_padding_mask=None):
        B, T_q, _ = query.shape
        T_k = key.shape[1]

        q = self.q_proj(query).view(B, T_q, self.n_heads, self.d_k).transpose(1, 2)
        k = self.k_proj(key).view(B, T_k, self.n_heads, self.d_k).transpose(1, 2)
        v = self.v_proj(value).view(B, T_k, self.n_heads, self.d_k).transpose(1, 2)

        # Scaled dot-product attention
        scores = torch.matmul(q, k.transpose(-2, -1)) * self.scale  # (B, H, T_q, T_k)

        if attn_mask is not None:
            # attn_mask: (T_q, T_k) bool — True means "mask out"
            scores = scores.masked_fill(attn_mask.unsqueeze(0).unsqueeze(0), float('-inf'))

        if key_padding_mask is not None:
            # key_padding_mask: (B, T_k) bool — True means padding
            scores = scores.masked_fill(key_padding_mask.unsqueeze(1).unsqueeze(2), float('-inf'))

        attn = torch.softmax(scores, dim=-1)
        out = torch.matmul(attn, v)  # (B, H, T_q, d_k)
        out = out.transpose(1, 2).contiguous().view(B, T_q, -1)
        return self.out_proj(out)


class ManualEncoderLayer(nn.Module):
    def __init__(self, layer: nn.TransformerEncoderLayer):
        super().__init__()
        self.self_attn = ManualMHA(layer.self_attn)
        self.norm1 = layer.norm1
        self.norm2 = layer.norm2
        self.linear1 = layer.linear1
        self.linear2 = layer.linear2
        self.activation = layer.activation

    def forward(self, src, src_key_padding_mask=None):
        # Post-norm: x = norm(x + sublayer(x))
        attn_out = self.self_attn(src, src, src, key_padding_mask=src_key_padding_mask)
        x = self.norm1(src + attn_out)
        ff_out = self.linear2(self.activation(self.linear1(x)))
        x = self.norm2(x + ff_out)
        return x


class ManualDecoderLayer(nn.Module):
    def __init__(self, layer: nn.TransformerDecoderLayer):
        super().__init__()
        self.self_attn = ManualMHA(layer.self_attn)
        self.cross_attn = ManualMHA(layer.multihead_attn)
        self.norm1 = layer.norm1
        self.norm2 = layer.norm2
        self.norm3 = layer.norm3
        self.linear1 = layer.linear1
        self.linear2 = layer.linear2
        self.activation = layer.activation

    def forward(self, tgt, memory, tgt_mask=None, memory_key_padding_mask=None):
        sa_out = self.self_attn(tgt, tgt, tgt, attn_mask=tgt_mask)
        x = self.norm1(tgt + sa_out)
        ca_out = self.cross_attn(x, memory, memory, key_padding_mask=memory_key_padding_mask)
        x = self.norm2(x + ca_out)
        ff_out = self.linear2(self.activation(self.linear1(x)))
        x = self.norm3(x + ff_out)
        return x


class SwipeModelForExport(nn.Module):
    """Full model using only basic ops."""

    def __init__(self, model: SwipeTransformer):
        super().__init__()
        self.input_proj = model.input_proj
        self.enc_pos = model.enc_pos
        self.token_embed = model.token_embed
        self.dec_pos = model.dec_pos
        self.output_proj = model.output_proj

        self.enc_layers = nn.ModuleList([ManualEncoderLayer(l) for l in model.encoder.layers])
        self.dec_layers = nn.ModuleList([ManualDecoderLayer(l) for l in model.decoder.layers])

    def forward(self, features, stroke_len, target_tokens):
        max_len = features.size(1)

        # Stroke padding mask
        positions = torch.arange(max_len, device=features.device).unsqueeze(0)
        stroke_mask = positions >= stroke_len.unsqueeze(1)

        # Encode
        x = self.input_proj(features)
        x = self.enc_pos(x)
        for layer in self.enc_layers:
            x = layer(x, src_key_padding_mask=stroke_mask)
        memory = x

        # Decode
        dec_input = target_tokens[:, :-1]
        tgt_len = dec_input.size(1)
        tgt_mask = torch.triu(torch.ones(tgt_len, tgt_len, device=features.device), diagonal=1).bool()

        tgt_embed = self.token_embed(dec_input)
        tgt_embed = self.dec_pos(tgt_embed)

        x = tgt_embed
        for layer in self.dec_layers:
            x = layer(x, memory, tgt_mask=tgt_mask, memory_key_padding_mask=stroke_mask)

        return self.output_proj(x)


def export_to_coreml(checkpoint_path: str, output_dir: str):
    import coremltools as ct

    print(f"Loading checkpoint: {checkpoint_path}")
    ckpt = torch.load(checkpoint_path, map_location="cpu", weights_only=True)

    config = ckpt.get("config", {})
    model = SwipeTransformer(
        d_model=config.get("d_model", 128),
        n_heads=config.get("n_heads", 4),
        n_layers=config.get("n_layers", 3),
        input_dim=config.get("input_dim", 29),
    )
    model.load_state_dict(ckpt["model_state_dict"])
    model.eval()

    export_model = SwipeModelForExport(model)
    export_model.eval()

    target_len = MAX_WORD_LEN + 2
    features = torch.randn(1, MAX_STROKE_LEN, 29)
    stroke_len = torch.tensor([40], dtype=torch.long)
    target_tokens = torch.full((1, target_len), SOS_TOKEN, dtype=torch.long)

    # Verify
    with torch.no_grad():
        orig = model(features, stroke_len, target_tokens)
        export = export_model(features, stroke_len, target_tokens)
        diff = (orig - export).abs().max().item()
        print(f"Export wrapper vs original: max diff = {diff:.2e}")
        assert diff < 1e-4, f"Too large: {diff}"

    # Trace
    print("Tracing...")
    with torch.no_grad():
        traced = torch.jit.trace(export_model, (features, stroke_len, target_tokens))
        tdiff = (export - traced(features, stroke_len, target_tokens)).abs().max().item()
        print(f"Traced vs wrapper: max diff = {tdiff:.2e}")

    # Convert
    print("Converting to Core ML...")
    cml_model = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="features", shape=(1, MAX_STROKE_LEN, 29)),
            ct.TensorType(name="stroke_len", shape=(1,)),
            ct.TensorType(name="target_tokens", shape=(1, target_len)),
        ],
        outputs=[ct.TensorType(name="logits")],
        minimum_deployment_target=ct.target.macOS14,
        convert_to="mlprogram",
    )

    cml_model.author = "ControllerKeys"
    cml_model.short_description = "Swipe-to-text decoder for on-screen keyboard"
    cml_model.version = "1.0"

    mlpackage_path = os.path.join(output_dir, "SwipeTyping.mlpackage")
    cml_model.save(mlpackage_path)

    total_size = sum(
        os.path.getsize(os.path.join(dp, f))
        for dp, _, fns in os.walk(mlpackage_path) for f in fns
    )
    print(f"\nSaved: {mlpackage_path} ({total_size / 1e6:.1f} MB)")

    # Sanity check
    pred = cml_model.predict({
        "features": np.random.randn(1, MAX_STROKE_LEN, 29).astype(np.float32),
        "stroke_len": np.array([40], dtype=np.int32),
        "target_tokens": np.full((1, target_len), SOS_TOKEN, dtype=np.int32),
    })
    print(f"Core ML output shape: {pred['logits'].shape}")
    print("Verification passed!")
    return mlpackage_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", default="checkpoints/best_model.pt")
    parser.add_argument("--output-dir", default="exported")
    args = parser.parse_args()
    os.makedirs(args.output_dir, exist_ok=True)
    export_to_coreml(args.checkpoint, args.output_dir)
    print("\nExport complete!")


if __name__ == "__main__":
    main()
