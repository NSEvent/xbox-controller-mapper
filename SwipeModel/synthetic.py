"""
Synthetic swipe data generator using minimum-jerk trajectories.

Generates smooth paths between key centers with Gaussian noise for
vocabulary coverage. Uses the minimum-jerk (quintic polynomial) profile
which models natural human pointing movements.
"""

import math
import random
import numpy as np

from keyboard_layout import LAYOUT, ALPHABET, key_proximity


def minimum_jerk_trajectory(
    start: tuple[float, float],
    end: tuple[float, float],
    n_points: int = 10,
) -> list[tuple[float, float]]:
    """
    Generate a minimum-jerk trajectory between two points.

    The minimum-jerk model produces smooth, bell-shaped velocity profiles
    that closely match natural human arm/finger movements.
    """
    points = []
    for i in range(n_points):
        t = i / max(n_points - 1, 1)
        # Minimum-jerk basis: 10t^3 - 15t^4 + 6t^5
        s = 10 * t**3 - 15 * t**4 + 6 * t**5
        x = start[0] + (end[0] - start[0]) * s
        y = start[1] + (end[1] - start[1]) * s
        points.append((x, y))
    return points


def generate_swipe(
    word: str,
    noise_std: float = 0.015,
    points_per_segment: int = 8,
    time_per_segment: float = 0.08,
) -> list[tuple[float, float, float]]:
    """
    Generate a synthetic swipe trace for a word.

    Args:
        word: The word to trace (uppercase letters)
        noise_std: Standard deviation of Gaussian noise added to points
        points_per_segment: Number of interpolated points between key centers
        time_per_segment: Simulated time per segment in seconds

    Returns:
        List of (x, y, dt) tuples in normalized coordinates
    """
    word = word.upper()
    if not word or not all(ch in LAYOUT for ch in word):
        return []

    # Get key centers for each letter
    centers = [LAYOUT[ch] for ch in word]

    # Remove consecutive duplicates (e.g., "LETTER" -> L,E,T,E,R path)
    path_centers = [centers[0]]
    for c in centers[1:]:
        if c != path_centers[-1]:
            path_centers.append(c)

    all_points = []
    dt = time_per_segment / points_per_segment

    for seg_idx in range(len(path_centers) - 1):
        start = path_centers[seg_idx]
        end = path_centers[seg_idx + 1]

        # Vary points per segment by distance
        dist = math.sqrt((end[0] - start[0]) ** 2 + (end[1] - start[1]) ** 2)
        n_pts = max(4, int(points_per_segment * (dist / 0.3)))
        n_pts = min(n_pts, 20)

        traj = minimum_jerk_trajectory(start, end, n_pts)

        # Skip first point of subsequent segments to avoid duplicates
        start_idx = 0 if seg_idx == 0 else 1
        for i in range(start_idx, len(traj)):
            x, y = traj[i]
            # Add Gaussian noise
            x += random.gauss(0, noise_std)
            y += random.gauss(0, noise_std)
            # Clamp to valid range
            x = max(0.0, min(1.0, x))
            y = max(0.0, min(1.0, y))
            actual_dt = 0.0 if (seg_idx == 0 and i == 0) else dt
            all_points.append((x, y, actual_dt))

    return all_points


def generate_synthetic_dataset(
    vocab_path: str = "vocab.txt",
    max_words: int = 50000,
    augment_factor: int = 2,
) -> list[dict]:
    """
    Generate synthetic swipe data for words in the vocabulary.

    Args:
        vocab_path: Path to vocabulary file (one word per line)
        max_words: Maximum number of words to use
        augment_factor: Number of variants to generate per word

    Returns:
        List of dicts with 'points' and 'word' keys
    """
    with open(vocab_path, "r") as f:
        words = [line.strip().upper() for line in f if line.strip()]

    # Filter to alpha-only words
    words = [w for w in words if w.isalpha() and len(w) >= 2]
    words = words[:max_words]

    samples = []
    for word in words:
        for variant in range(augment_factor):
            # Vary noise level across variants
            noise = random.uniform(0.008, 0.025)
            points = generate_swipe(word, noise_std=noise)
            if points and len(points) >= 2:
                samples.append({"points": points, "word": word})

    random.shuffle(samples)
    print(f"Generated {len(samples)} synthetic samples from {len(words)} words")
    return samples


if __name__ == "__main__":
    # Demo: generate a swipe for "HELLO"
    points = generate_swipe("HELLO")
    print(f"Swipe for 'HELLO': {len(points)} points")
    for i, (x, y, dt) in enumerate(points[:5]):
        print(f"  [{i}] x={x:.4f} y={y:.4f} dt={dt:.4f}")

    # Generate small dataset
    samples = generate_synthetic_dataset(max_words=100, augment_factor=2)
    print(f"\nGenerated {len(samples)} total samples")
