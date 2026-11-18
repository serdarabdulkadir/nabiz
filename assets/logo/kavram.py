#!/usr/bin/env python3
"""Logo kavramlari: ORBIO ana ikonunun zemini (squircle, cam kenar, golge) + yeni glif. Cikti: kavram-<ad>.svg"""
import math, re, pathlib, sys
SRC = pathlib.Path.home() / "Library/bt-ekosistem/assets/logo/final/icon-master.svg"
OUT = pathlib.Path(__file__).parent
m = SRC.read_text()
base = m[:m.index('<g filter="url(#sf)">')].replace('aria-label="BT Ekosistem"', 'aria-label="{label}"')
C = 512
def pt(r, a): return C + r * math.cos(math.radians(a)), C + r * math.sin(math.radians(a))
def arc(r, a0, a1):
    x0, y0 = pt(r, a0); x1, y1 = pt(r, a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return f"M{x0:.1f} {y0:.1f} A{r} {r} 0 {large} 1 {x1:.1f} {y1:.1f}"
def stroke(d, w, g="sR", extra=""): return f'<path d="{d}" fill="none" stroke="url(#{g})" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round" {extra}/>'
def track(d, w): return f'<path d="{d}" fill="none" stroke="#FFFFFF" stroke-opacity="0.08" stroke-width="{w}" stroke-linecap="round"/>'
ecg = "M232 540 L388 540 L440 420 L520 676 L592 330 L646 540 L792 540"
G = {}
# A: nabiz cizgisi
G["nabiz"] = ([], [stroke(ecg, 66)])
# B: uc halka (CPU / RAM / Disk)
rings = [(272, .78), (190, .60), (108, .44)]
G["halkalar"] = ([track(arc(r, -90, 269.9), 54) for r, _ in rings],
                 [stroke(arc(r, -90, -90 + 360 * f), 54, "sR" if i == 0 else "sL") for i, (r, f) in enumerate(rings)])
# C: gosterge (270 derece) + igne
fill_to = 135 + 270 * .68
nx, ny = pt(190, fill_to)
G["gosterge"] = ([track(arc(290, 135, 405), 72)],
                 [stroke(arc(290, 135, fill_to), 72), stroke(f"M512 512 L{nx:.1f} {ny:.1f}", 44, "sL"), '<circle cx="512" cy="512" r="60" fill="url(#sR)"/>'])
# D: ORBIO ailesi: parantez yaylari + ortada nabiz
small = "M420 524 L456 524 L478 452 L514 600 L548 424 L572 524 L604 524"
G["aile"] = ([], ['<path d="M400.00 317.96 A224.00 224.00 0 0 0 400.00 706.04" fill="none" stroke="url(#sL)" stroke-width="72" stroke-linecap="round"/>',
                  '<path d="M624.00 317.96 A224.00 224.00 0 0 1 624.00 706.04" fill="none" stroke="url(#sR)" stroke-width="72" stroke-linecap="round"/>',
                  stroke(small, 40)])
for name, (back, glyph) in G.items():
    sheen = [g.replace('url(#sR)', 'url(#sS)').replace('url(#sL)', 'url(#sS)') for g in glyph]
    svg = base.format(label=name) + "".join(back) + '<g filter="url(#sf)">' + "".join(glyph) + "</g><g>" + "".join(sheen) + "</g></svg>"
    (OUT / f"kavram-{name}.svg").write_text(svg)
    print(name, len(svg))
