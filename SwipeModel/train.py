"""
Training loop for the swipe-to-text model.

Trains with 70% FUTO real data + 30% synthetic data.
Uses cross-entropy loss with beam search validation.
"""

import os
import time
import random
import argparse

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, ConcatDataset, Subset

from keyboard_layout import LAYOUT
from dataset import (
    SwipeDataset,
    load_futo_dataset,
    PAD_TOKEN,
    SOS_TOKEN,
    EOS_TOKEN,
    VOCAB_SIZE,
)
from synthetic import generate_synthetic_dataset
from model import SwipeTransformer, tokens_to_word, count_parameters, estimate_model_size_mb


def set_seed(seed: int = 42):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def compute_accuracy(model, dataloader, device, beam_width=3, max_batches=50):
    """Compute word-level accuracy using beam search."""
    model.eval()
    correct = 0
    total = 0

    with torch.no_grad():
        for batch_idx, batch in enumerate(dataloader):
            if batch_idx >= max_batches:
                break

            features = batch["features"].to(device)
            stroke_len = batch["stroke_len"].to(device)
            target = batch["target"]

            results = model.predict(features, stroke_len, beam_width=beam_width)

            for i, beams in enumerate(results):
                # Ground truth
                gt_tokens = target[i].tolist()
                gt_word = tokens_to_word(gt_tokens)

                if beams:
                    pred_word = tokens_to_word(beams[0][0])
                    if pred_word == gt_word:
                        correct += 1
                total += 1

    return correct / max(total, 1)


def train(args):
    set_seed(args.seed)
    device = torch.device(args.device)
    print(f"Training on: {device}")

    # Load datasets
    print("\n--- Loading data ---")
    futo_samples = load_futo_dataset(max_samples=args.max_futo_samples)

    synth_target = int(len(futo_samples) * 0.43)  # 30% of total = 0.3/0.7 * real
    synth_samples = generate_synthetic_dataset(
        vocab_path=args.vocab_path,
        max_words=args.max_vocab_words,
        augment_factor=max(1, synth_target // args.max_vocab_words + 1),
    )
    synth_samples = synth_samples[:synth_target]

    print(f"Real samples: {len(futo_samples)}")
    print(f"Synthetic samples: {len(synth_samples)}")
    real_pct = len(futo_samples) / (len(futo_samples) + len(synth_samples)) * 100
    print(f"Mix: {real_pct:.0f}% real, {100-real_pct:.0f}% synthetic")

    # Split into train/val
    all_samples = futo_samples + synth_samples
    random.shuffle(all_samples)

    val_size = min(5000, len(all_samples) // 10)
    val_samples = all_samples[:val_size]
    train_samples = all_samples[val_size:]

    train_dataset = SwipeDataset(train_samples, augment=True)
    val_dataset = SwipeDataset(val_samples, augment=False)

    train_loader = DataLoader(
        train_dataset,
        batch_size=args.batch_size,
        shuffle=True,
        num_workers=args.num_workers,
        pin_memory=True,
        drop_last=True,
    )
    val_loader = DataLoader(
        val_dataset,
        batch_size=args.batch_size,
        shuffle=False,
        num_workers=args.num_workers,
        pin_memory=True,
    )

    # Create model
    model = SwipeTransformer(
        d_model=args.d_model,
        n_heads=args.n_heads,
        n_layers=args.n_layers,
        dropout=args.dropout,
    ).to(device)

    n_params = count_parameters(model)
    size_mb = estimate_model_size_mb(model)
    print(f"\nModel: {n_params:,} parameters, ~{size_mb:.1f} MB")

    # Optimizer and scheduler
    optimizer = torch.optim.AdamW(
        model.parameters(), lr=args.lr, weight_decay=args.weight_decay
    )
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
        optimizer, T_max=args.epochs, eta_min=args.lr * 0.01
    )

    criterion = nn.CrossEntropyLoss(ignore_index=PAD_TOKEN)

    best_val_loss = float("inf")
    best_accuracy = 0.0

    os.makedirs(args.output_dir, exist_ok=True)

    print(f"\n--- Training for {args.epochs} epochs ---")
    for epoch in range(1, args.epochs + 1):
        model.train()
        epoch_loss = 0.0
        n_batches = 0
        t0 = time.time()

        for batch in train_loader:
            features = batch["features"].to(device)
            stroke_len = batch["stroke_len"].to(device)
            target = batch["target"].to(device)

            # Forward: predict target[1:] from target[:-1]
            logits = model(features, stroke_len, target)  # (B, T-1, V)

            # Loss: compare logits against target[1:]
            loss = criterion(
                logits.reshape(-1, VOCAB_SIZE),
                target[:, 1:].reshape(-1),
            )

            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()

            epoch_loss += loss.item()
            n_batches += 1

        scheduler.step()

        avg_loss = epoch_loss / max(n_batches, 1)
        elapsed = time.time() - t0

        # Validation
        model.eval()
        val_loss = 0.0
        val_batches = 0
        with torch.no_grad():
            for batch in val_loader:
                features = batch["features"].to(device)
                stroke_len = batch["stroke_len"].to(device)
                target = batch["target"].to(device)

                logits = model(features, stroke_len, target)
                loss = criterion(
                    logits.reshape(-1, VOCAB_SIZE),
                    target[:, 1:].reshape(-1),
                )
                val_loss += loss.item()
                val_batches += 1

        avg_val_loss = val_loss / max(val_batches, 1)

        # Beam search accuracy every 5 epochs
        accuracy = 0.0
        acc_str = ""
        if epoch % 5 == 0 or epoch == args.epochs:
            accuracy = compute_accuracy(model, val_loader, device)
            acc_str = f"  acc={accuracy:.3f}"
            if accuracy > best_accuracy:
                best_accuracy = accuracy

        lr = scheduler.get_last_lr()[0]
        print(
            f"Epoch {epoch:3d}/{args.epochs} | "
            f"loss={avg_loss:.4f} | val_loss={avg_val_loss:.4f}{acc_str} | "
            f"lr={lr:.6f} | {elapsed:.1f}s"
        )

        # Save best model
        if avg_val_loss < best_val_loss:
            best_val_loss = avg_val_loss
            save_path = os.path.join(args.output_dir, "best_model.pt")
            torch.save(
                {
                    "epoch": epoch,
                    "model_state_dict": model.state_dict(),
                    "optimizer_state_dict": optimizer.state_dict(),
                    "val_loss": avg_val_loss,
                    "accuracy": accuracy,
                    "config": {
                        "d_model": args.d_model,
                        "n_heads": args.n_heads,
                        "n_layers": args.n_layers,
                        "input_dim": 29,
                    },
                },
                save_path,
            )
            print(f"  -> Saved best model (val_loss={avg_val_loss:.4f})")

    # Save final model
    final_path = os.path.join(args.output_dir, "final_model.pt")
    torch.save(
        {
            "epoch": args.epochs,
            "model_state_dict": model.state_dict(),
            "config": {
                "d_model": args.d_model,
                "n_heads": args.n_heads,
                "n_layers": args.n_layers,
                "input_dim": 29,
            },
        },
        final_path,
    )

    print(f"\nTraining complete!")
    print(f"  Best val loss: {best_val_loss:.4f}")
    print(f"  Best accuracy: {best_accuracy:.3f}")
    print(f"  Models saved to: {args.output_dir}/")
    return model


def main():
    parser = argparse.ArgumentParser(description="Train swipe-to-text model")
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument("--weight-decay", type=float, default=0.01)
    parser.add_argument("--d-model", type=int, default=128)
    parser.add_argument("--n-heads", type=int, default=4)
    parser.add_argument("--n-layers", type=int, default=3)
    parser.add_argument("--dropout", type=float, default=0.1)
    parser.add_argument("--max-futo-samples", type=int, default=None)
    parser.add_argument("--max-vocab-words", type=int, default=50000)
    parser.add_argument("--vocab-path", type=str, default="vocab.txt")
    parser.add_argument("--output-dir", type=str, default="checkpoints")
    parser.add_argument("--device", type=str, default="auto")
    parser.add_argument("--num-workers", type=int, default=4)
    parser.add_argument("--seed", type=int, default=42)

    args = parser.parse_args()

    if args.device == "auto":
        if torch.cuda.is_available():
            args.device = "cuda"
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            args.device = "mps"
        else:
            args.device = "cpu"

    train(args)


if __name__ == "__main__":
    main()
