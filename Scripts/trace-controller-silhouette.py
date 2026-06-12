#!/usr/bin/env python3
"""Convert a potrace SVG of a controller silhouette into SwiftUI Path code.

Part of the controller-minimap pipeline — see
docs/internal/adding-controller-minimaps.md for the full process.

Typical use:
    # 1. Make a clean black-on-white mask from a front-on product photo
    magick photo.jpg -colorspace Gray -threshold 60% mask.png
    #    (white/transparent-bg photos: use -alpha extract, or mask by
    #     saturation for colored bodies; fill interior holes by flood-filling
    #     the border and inverting; see the playbook for the recipes)

    # 2. Smooth and trace
    magick mask.png -bordercolor white -border 4 \
        -fill red -floodfill +0+0 white -fill black +opaque red \
        -fill white -opaque red -shave 4x4 -blur 0x6 -threshold 50% mask.pbm
    potrace mask.pbm -s --opttolerance 2.5 --alphamax 1.2 -o body.svg

    # 3. Emit Swift (largest outer subpath only, normalized to its bbox)
    python3 Scripts/trace-controller-silhouette.py body
    #    prints `p.move/addCurve` lines + the aspect ratio for the
    #    Shape struct in ControllerBodyShapes.swift

Args are SVG basenames (without .svg) resolved in the current directory.
"""
import re
import sys


def parse_svg(filename):
    with open(filename) as f:
        svg = f.read()
    m = re.search(r'translate\(([-\d.]+),([-\d.]+)\)', svg)
    tx, ty = (float(m.group(1)), float(m.group(2))) if m else (0.0, 0.0)
    m = re.search(r'scale\(([-\d.]+),([-\d.]+)\)', svg)
    sx, sy = (float(m.group(1)), float(m.group(2))) if m else (1.0, 1.0)

    def xform(x, y):
        return (tx + sx * x, ty + sy * y)

    paths = re.findall(r'<path d="([^"]+)"', svg)
    subpaths = []
    for d in paths:
        tokens = re.findall(r'[MmCcLlZz]|-?[\d.]+', d)
        i = 0
        cur = None
        start = None
        segs = None  # list of ('move'|'curve'|'line', points)
        while i < len(tokens):
            t = tokens[i]
            if t in 'Mm':
                if segs:
                    subpaths.append(segs)
                x, y = float(tokens[i + 1]), float(tokens[i + 2])
                if t == 'm' and cur is not None:
                    x, y = cur[0] + x, cur[1] + y
                cur = (x, y)
                start = cur
                segs = [('move', [xform(*cur)])]
                i += 3
            elif t in 'Cc':
                rel = t == 'c'
                i += 1
                while i < len(tokens) and re.match(r'-?[\d.]+', tokens[i]):
                    pts = [float(tokens[i + k]) for k in range(6)]
                    if rel:
                        c1 = (cur[0] + pts[0], cur[1] + pts[1])
                        c2 = (cur[0] + pts[2], cur[1] + pts[3])
                        end = (cur[0] + pts[4], cur[1] + pts[5])
                    else:
                        c1, c2, end = (pts[0], pts[1]), (pts[2], pts[3]), (pts[4], pts[5])
                    segs.append(('curve', [xform(*c1), xform(*c2), xform(*end)]))
                    cur = end
                    i += 6
            elif t in 'Ll':
                rel = t == 'l'
                i += 1
                while i < len(tokens) and re.match(r'-?[\d.]+', tokens[i]):
                    x, y = float(tokens[i]), float(tokens[i + 1])
                    if rel:
                        x, y = cur[0] + x, cur[1] + y
                    segs.append(('line', [xform(x, y)]))
                    cur = (x, y)
                    i += 2
            elif t in 'Zz':
                cur = start
                i += 1
            else:
                i += 1
        if segs:
            subpaths.append(segs)
    return subpaths


def flatten_points(segs):
    pts = []
    for kind, points in segs:
        pts.extend(points)
    return pts


def signed_area(segs):
    pts = [p for kind, points in segs for p in points[-1:]]
    area = 0.0
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % len(pts)]
        area += x1 * y2 - x2 * y1
    return abs(area) / 2


def emit_swift(segs, name):
    pts = flatten_points(segs)
    minx = min(p[0] for p in pts)
    maxx = max(p[0] for p in pts)
    miny = min(p[1] for p in pts)
    maxy = max(p[1] for p in pts)
    w, h = maxx - minx, maxy - miny

    def norm(p):
        return ((p[0] - minx) / w, (p[1] - miny) / h)

    def fmt(p):
        x, y = norm(p)
        return f"CGPoint(x: w * {x:.4f}, y: h * {y:.4f})"

    lines = []
    for kind, points in segs:
        if kind == 'move':
            lines.append(f"p.move(to: {fmt(points[0])})")
        elif kind == 'line':
            lines.append(f"p.addLine(to: {fmt(points[0])})")
        else:
            c1, c2, end = points
            lines.append(
                f"p.addCurve(to: {fmt(end)}, control1: {fmt(c1)}, control2: {fmt(c2)})"
            )
    lines.append("p.closeSubpath()")
    body = "\n        ".join(lines)
    aspect = w / h
    print(f"// {name}: {len(segs)} segments, aspect w/h = {aspect:.4f}")
    print(body)
    print()
    return aspect


if __name__ == '__main__':
    for name in sys.argv[1:]:
        subpaths = parse_svg(f"{name}.svg")
        outer = max(subpaths, key=signed_area)
        emit_swift(outer, name)
