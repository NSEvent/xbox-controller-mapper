# Xiaomi RC003 minimap reference

`xiaomi-rc003-front.jpg`: straight-on product photo of Xiaomi Bluetooth Remote
2 Pro (RC003-MS), retrieved 2026-10-14 from the retailer's product gallery:

- Page: https://mi-shop.kg/product/pult-upravleniya-xiaomi-bluetooth-remote-2-pro-rc003-ms/
- Image: https://mi-shop.kg/wp-content/uploads/2026/09/Bez-imeni-1-2.jpg

The app renders a native SwiftUI vector, not this bitmap. Body bbox in the
800×800 photo: approximately x=328–473, y=115–685 (145×570). Button centers,
ring radii, rocker geometry, materials and thin etched glyphs were measured
from this same image. The blank center and cardinal dimples are intentional.

Silhouette conversion followed `docs/internal/adding-controller-minimaps.md`:
grayscale threshold 90%, close the top/bottom highlight gaps at the body
boundary, flood-fill the exterior to fill interior holes, blur 1.2 pixels,
potrace `--opttolerance 1.2 --alphamax 1.2`, then
`Scripts/trace-controller-silhouette.py`. Traced aspect 0.2548, within 0.002
of the measured 145/570 photo aspect. The final vector cleans the trace's
over-smoothed top-left segment into straight sides with circular 2 px corners
measured at the reference width; corner height does not stretch with body height.

Connector ports follow the visible controls: four cardinal points on the ring's
outer rim, and the facing horizontal midpoint of each circular key. Using sector
or circle bounding-box edges leaves gaps or points at the wrong part of the ring.
Label ports meet the facing glass edge at its midpoint. Regression checks cover
all four directions at multiple canvas scales; other layouts retain their
existing connector projection.

The photo is retained as a geometry/reference source; the product imagery
and Xiaomi marks belong to their respective owners.
