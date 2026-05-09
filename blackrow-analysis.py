from PIL import Image
import numpy as np

img = Image.open('MSU-MR/msu_mr_rgb_MSA_corrected.png')
arr = np.array(img)

# Find rows that are mostly black (average brightness < 10)
black_rows = []
for i, row in enumerate(arr):
    if row.mean() < 10:
        black_rows.append(i)

# Group into clusters
clusters = []
if black_rows:
    start = black_rows[0]
    prev = black_rows[0]
    for r in black_rows[1:]:
        if r - prev > 5:
            clusters.append((start, prev))
            start = r
        prev = r
    clusters.append((start, prev))

for s, e in clusters:
    mid = (s + e) // 2
    elapsed = mid / 3
    print(f"Rows {s}-{e} ({e-s+1} rows) | ~{elapsed:.0f}s from AOS | ~{elapsed/60:.1f} min")
