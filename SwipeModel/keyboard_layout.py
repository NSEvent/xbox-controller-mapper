"""
QWERTY keyboard layout matching ControllerKeys on-screen keyboard dimensions.

Key dimensions: width=68, height=60, spacing=8
Row offsets derived from special key widths:
  - QWERTY row: Tab key (width=95) + spacing
  - ASDF row: CapsLock key (width=112) + spacing
  - ZXCV row: Shift key (width=140) + spacing
"""

KEY_WIDTH = 68
KEY_HEIGHT = 60
KEY_SPACING = 8

# Row definitions: each row has an x-offset (from special key) and list of letter keys
# Offsets include the special key width + one spacing gap
ROWS = [
    {
        "offset": 95 + KEY_SPACING,   # Tab(95) + spacing
        "keys": list("QWERTYUIOP"),
        "y_index": 0,
    },
    {
        "offset": 112 + KEY_SPACING,  # CapsLock(112) + spacing
        "keys": list("ASDFGHJKL"),
        "y_index": 1,
    },
    {
        "offset": 140 + KEY_SPACING,  # Shift(140) + spacing
        "keys": list("ZXCVBNM"),
        "y_index": 2,
    },
]

# Total keyboard width (from number row: grave + 10 digits + minus + equal + backspace)
# = 13 * 68 + 107 (backspace) + 13 * 8 = 884 + 107 + 104 = 1095
# But for letter area normalization, we use the rightmost letter key edge
# as the practical bound.


def _compute_layout():
    """Compute pixel center coordinates for every letter key."""
    layout = {}
    for row in ROWS:
        x_start = row["offset"]
        y_center = row["y_index"] * (KEY_HEIGHT + KEY_SPACING) + KEY_HEIGHT / 2.0
        for i, key in enumerate(row["keys"]):
            x_center = x_start + i * (KEY_WIDTH + KEY_SPACING) + KEY_WIDTH / 2.0
            layout[key] = (x_center, y_center)
    return layout


# Pixel-space center coordinates for each letter key
LAYOUT_PX = _compute_layout()

# Compute bounding box for normalization (letter keys only)
_all_x = [v[0] for v in LAYOUT_PX.values()]
_all_y = [v[1] for v in LAYOUT_PX.values()]
_x_min = min(_all_x) - KEY_WIDTH / 2.0
_x_max = max(_all_x) + KEY_WIDTH / 2.0
_y_min = min(_all_y) - KEY_HEIGHT / 2.0
_y_max = max(_all_y) + KEY_HEIGHT / 2.0
LAYOUT_WIDTH = _x_max - _x_min
LAYOUT_HEIGHT = _y_max - _y_min


def _normalize(px_layout):
    """Normalize pixel coordinates to [0, 1] range based on letter-key bounding box."""
    normalized = {}
    for key, (x, y) in px_layout.items():
        nx = (x - _x_min) / LAYOUT_WIDTH
        ny = (y - _y_min) / LAYOUT_HEIGHT
        normalized[key] = (nx, ny)
    return normalized


# Normalized (0-1) center coordinates for each letter key
LAYOUT = _normalize(LAYOUT_PX)

# Ordered list of letters A-Z for consistent indexing
ALPHABET = list("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
LETTER_TO_IDX = {ch: i for i, ch in enumerate(ALPHABET)}

# Pre-computed normalized centers as a list indexed by ALPHABET order
CENTERS = [(LAYOUT[ch][0], LAYOUT[ch][1]) for ch in ALPHABET]


def nearest_key(x: float, y: float) -> str:
    """Find the nearest letter key to a normalized (x, y) coordinate."""
    best_key = "A"
    best_dist = float("inf")
    for ch, (cx, cy) in LAYOUT.items():
        d = (x - cx) ** 2 + (y - cy) ** 2
        if d < best_dist:
            best_dist = d
            best_key = ch
    return best_key


def key_proximity(x: float, y: float) -> list[float]:
    """Compute 26-dim proximity vector: inverse distance to each key center (A-Z)."""
    import math

    prox = []
    for cx, cy in CENTERS:
        d = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
        prox.append(1.0 / (1.0 + d * 10.0))  # Scale factor for useful gradient
    return prox


if __name__ == "__main__":
    print("ControllerKeys Keyboard Layout (normalized 0-1 coordinates):")
    print(f"  Pixel bounding box: x=[{_x_min:.0f}, {_x_max:.0f}], y=[{_y_min:.0f}, {_y_max:.0f}]")
    print(f"  Layout size: {LAYOUT_WIDTH:.0f} x {LAYOUT_HEIGHT:.0f} px")
    print()
    for row in ROWS:
        for key in row["keys"]:
            nx, ny = LAYOUT[key]
            px, py = LAYOUT_PX[key]
            print(f"  {key}: pixel=({px:6.1f}, {py:5.1f})  norm=({nx:.4f}, {ny:.4f})")
        print()
