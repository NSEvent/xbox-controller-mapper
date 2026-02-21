"""
Swipe-to-text Transformer model.

Encoder-decoder architecture with:
- Encoder: processes swipe trace features (x, y, dt, 26-dim key proximity)
- Decoder: character-level autoregressive decoder

Target size: <10MB for Core ML deployment.
"""

import math
import torch
import torch.nn as nn
import torch.nn.functional as F

from dataset import VOCAB_SIZE, MAX_STROKE_LEN, MAX_WORD_LEN, SOS_TOKEN, EOS_TOKEN, PAD_TOKEN


class PositionalEncoding(nn.Module):
    """Sinusoidal positional encoding."""

    def __init__(self, d_model: int, max_len: int = 200):
        super().__init__()
        pe = torch.zeros(max_len, d_model)
        position = torch.arange(0, max_len, dtype=torch.float).unsqueeze(1)
        div_term = torch.exp(
            torch.arange(0, d_model, 2).float() * (-math.log(10000.0) / d_model)
        )
        pe[:, 0::2] = torch.sin(position * div_term)
        pe[:, 1::2] = torch.cos(position * div_term)
        self.register_buffer("pe", pe.unsqueeze(0))  # (1, max_len, d_model)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return x + self.pe[:, : x.size(1)]


class SwipeTransformer(nn.Module):
    """
    Encoder-decoder Transformer for swipe-to-text.

    Args:
        d_model: Model dimension (default 128)
        n_heads: Number of attention heads (default 4)
        n_layers: Number of encoder/decoder layers (default 3)
        input_dim: Input feature dimension (default 29 = x,y,dt + 26 proximity)
        dropout: Dropout rate
    """

    def __init__(
        self,
        d_model: int = 128,
        n_heads: int = 4,
        n_layers: int = 3,
        input_dim: int = 29,
        dropout: float = 0.1,
    ):
        super().__init__()
        self.d_model = d_model
        self.input_dim = input_dim

        # Encoder
        self.input_proj = nn.Linear(input_dim, d_model)
        self.enc_pos = PositionalEncoding(d_model, max_len=MAX_STROKE_LEN + 10)
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model,
            nhead=n_heads,
            dim_feedforward=d_model * 4,
            dropout=dropout,
            batch_first=True,
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=n_layers, enable_nested_tensor=False)

        # Decoder
        self.token_embed = nn.Embedding(VOCAB_SIZE, d_model, padding_idx=PAD_TOKEN)
        self.dec_pos = PositionalEncoding(d_model, max_len=MAX_WORD_LEN + 10)
        decoder_layer = nn.TransformerDecoderLayer(
            d_model=d_model,
            nhead=n_heads,
            dim_feedforward=d_model * 4,
            dropout=dropout,
            batch_first=True,
        )
        self.decoder = nn.TransformerDecoder(decoder_layer, num_layers=n_layers)

        # Output projection
        self.output_proj = nn.Linear(d_model, VOCAB_SIZE)

        self._init_weights()

    def _init_weights(self):
        for p in self.parameters():
            if p.dim() > 1:
                nn.init.xavier_uniform_(p)

    def _make_causal_mask(self, size: int, device: torch.device) -> torch.Tensor:
        mask = torch.triu(torch.ones(size, size, device=device), diagonal=1).bool()
        return mask

    def encode(
        self, features: torch.Tensor, stroke_mask: torch.Tensor = None
    ) -> torch.Tensor:
        """
        Encode swipe trace.

        Args:
            features: (batch, seq_len, input_dim)
            stroke_mask: (batch, seq_len) True = padding position

        Returns:
            memory: (batch, seq_len, d_model)
        """
        x = self.input_proj(features)
        x = self.enc_pos(x)
        memory = self.encoder(x, src_key_padding_mask=stroke_mask)
        return memory

    def decode(
        self,
        target: torch.Tensor,
        memory: torch.Tensor,
        stroke_mask: torch.Tensor = None,
    ) -> torch.Tensor:
        """
        Decode characters from encoder memory.

        Args:
            target: (batch, target_len) token indices
            memory: (batch, src_len, d_model)
            stroke_mask: (batch, src_len)

        Returns:
            logits: (batch, target_len, vocab_size)
        """
        tgt_len = target.size(1)
        tgt_mask = self._make_causal_mask(tgt_len, target.device)

        tgt_embed = self.token_embed(target)
        tgt_embed = self.dec_pos(tgt_embed)

        output = self.decoder(
            tgt_embed,
            memory,
            tgt_mask=tgt_mask,
            memory_key_padding_mask=stroke_mask,
        )
        logits = self.output_proj(output)
        return logits

    def forward(
        self,
        features: torch.Tensor,
        stroke_len: torch.Tensor,
        target: torch.Tensor,
    ) -> torch.Tensor:
        """
        Full forward pass.

        Args:
            features: (batch, max_stroke_len, input_dim)
            stroke_len: (batch,) actual stroke lengths
            target: (batch, max_word_len+2) token indices (with SOS prefix)

        Returns:
            logits: (batch, target_len-1, vocab_size) predictions for target[1:]
        """
        batch_size = features.size(0)
        max_len = features.size(1)

        # Create stroke padding mask
        positions = torch.arange(max_len, device=features.device).unsqueeze(0)
        stroke_mask = positions >= stroke_len.unsqueeze(1)  # True = padding

        memory = self.encode(features, stroke_mask)

        # Teacher forcing: input is target[:-1], predict target[1:]
        dec_input = target[:, :-1]
        logits = self.decode(dec_input, memory, stroke_mask)
        return logits

    @torch.no_grad()
    def predict(
        self,
        features: torch.Tensor,
        stroke_len: torch.Tensor,
        max_len: int = MAX_WORD_LEN + 2,
        beam_width: int = 5,
    ) -> list[list[tuple[list[int], float]]]:
        """
        Beam search decoding.

        Args:
            features: (batch, max_stroke_len, input_dim)
            stroke_len: (batch,)
            max_len: Maximum decode length
            beam_width: Beam width

        Returns:
            List of beam results per batch item.
            Each beam result is a list of (token_ids, score) tuples.
        """
        self.eval()
        batch_size = features.size(0)
        max_stroke = features.size(1)
        device = features.device

        positions = torch.arange(max_stroke, device=device).unsqueeze(0)
        stroke_mask = positions >= stroke_len.unsqueeze(1)
        memory = self.encode(features, stroke_mask)

        all_results = []

        for b in range(batch_size):
            mem = memory[b : b + 1]  # (1, src_len, d_model)
            smask = stroke_mask[b : b + 1]  # (1, src_len)

            # Each beam: (tokens, cumulative_log_prob)
            beams = [([SOS_TOKEN], 0.0)]
            finished = []

            for step in range(max_len):
                candidates = []
                for tokens, score in beams:
                    if tokens[-1] == EOS_TOKEN:
                        finished.append((tokens, score))
                        continue

                    tgt = torch.tensor([tokens], dtype=torch.long, device=device)
                    logits = self.decode(tgt, mem, smask)  # (1, seq, vocab)
                    log_probs = F.log_softmax(logits[0, -1], dim=-1)

                    topk = torch.topk(log_probs, beam_width)
                    for val, idx in zip(topk.values, topk.indices):
                        new_tokens = tokens + [idx.item()]
                        new_score = score + val.item()
                        candidates.append((new_tokens, new_score))

                if not candidates:
                    break

                # Keep top beams
                candidates.sort(key=lambda x: x[1], reverse=True)
                beams = candidates[:beam_width]

            # Add any remaining beams
            finished.extend(beams)
            finished.sort(key=lambda x: x[1] / max(len(x[0]), 1), reverse=True)
            all_results.append(finished[:beam_width])

        return all_results


def tokens_to_word(tokens: list[int]) -> str:
    """Convert token indices to a word string."""
    chars = []
    for t in tokens:
        if t == SOS_TOKEN or t == PAD_TOKEN:
            continue
        if t == EOS_TOKEN:
            break
        if 1 <= t <= 26:
            chars.append(chr(ord("A") + t - 1))
    return "".join(chars)


def count_parameters(model: nn.Module) -> int:
    return sum(p.numel() for p in model.parameters())


def estimate_model_size_mb(model: nn.Module) -> float:
    """Estimate model size in MB (float32)."""
    return count_parameters(model) * 4 / (1024 * 1024)


if __name__ == "__main__":
    model = SwipeTransformer()
    n_params = count_parameters(model)
    size_mb = estimate_model_size_mb(model)
    print(f"SwipeTransformer: {n_params:,} parameters, ~{size_mb:.1f} MB")

    # Test forward pass
    batch = 4
    features = torch.randn(batch, 80, 29)
    stroke_len = torch.tensor([40, 60, 30, 50])
    target = torch.randint(0, VOCAB_SIZE, (batch, MAX_WORD_LEN + 2))
    target[:, 0] = SOS_TOKEN

    logits = model(features, stroke_len, target)
    print(f"Logits shape: {logits.shape}")  # (4, 21, 29)
