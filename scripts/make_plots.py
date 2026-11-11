#!/usr/bin/env python3
"""Wall-clock execution time (cycles / Fmax) per kernel, from results/*.json."""
import json
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent
bench = json.loads((ROOT / "results/bench.json").read_text())
ppa = json.loads((ROOT / "results/ppa.json").read_text())

CONFIGS = [  # (bench/ppa key, label, kernel suffix used for the MAC kernels)
    ("rv32imc_mul",     "Iterative MUL\n(PicoRV32 default)", "c"),
    ("rv32imc_fastmul", "DSP fast MUL\n(baseline)",          "c"),
    ("fastmul_mac_p1",  "MAC, 2-cycle",                      "mac16x2"),
    ("fastmul_mac_p2",  "MAC, 3-cycle\n(DSP-pipelined)",     "mac16x2"),
]
KERNELS = [("dot16", "int16 dot product, N = 1024"), ("matmul16", "16×16 int16 matrix multiply")]

SURFACE, INK, MUTED, GRID = "#fcfcfb", "#0b0b0b", "#6b6a64", "#e4e3de"
ACCENT, NEUTRAL = "#2a78d6", "#b9b8b0"

plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "text.color": INK,
                     "axes.labelcolor": MUTED, "xtick.color": MUTED, "ytick.color": MUTED})
fig, axes = plt.subplots(1, 2, figsize=(11, 4.4), facecolor=SURFACE)
for ax, (kern, title) in zip(axes, KERNELS):
    labels, times, colors = [], [], []
    for key, label, suffix in CONFIGS:
        # baseline = plain-C kernel inside the MAC firmware image (identical code
        # layout to the MAC kernels; the C kernel never touches the MAC unit)
        src = "fastmul_mac_p2" if key == "rv32imc_fastmul" else key
        cycles = bench[src]["kernels"][f"{kern}_{suffix}"]["cycles"]
        fmax = ppa[key]["best"]["fmax_mhz"]
        labels.append(label)
        times.append(cycles / fmax)  # microseconds
        colors.append(ACCENT if key == "fastmul_mac_p2" else NEUTRAL)
    base = times[1]
    bars = ax.bar(range(len(times)), times, color=colors, width=0.62, zorder=2)
    for i, (b, t) in enumerate(zip(bars, times)):
        txt = f"{t:,.0f} µs" + (f"\n{base / t:.2f}× vs baseline" if i >= 2 else "")
        ax.text(b.get_x() + b.get_width() / 2, t + max(times) * 0.02, txt,
                ha="center", va="bottom", fontsize=9, color=INK)
    ax.set_xticks(range(len(labels)), labels, fontsize=9)
    ax.set_title(title, loc="left", fontsize=11, color=INK, pad=10)
    ax.set_ylabel("execution time (µs) = cycles / Fmax")
    ax.set_ylim(0, max(times) * 1.25)
    ax.set_facecolor(SURFACE)
    ax.grid(axis="y", color=GRID, linewidth=0.8, zorder=0)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.tick_params(length=0)
fig.suptitle("PicoRV32 on Zynq-7020: custom MAC instruction vs. RV32IMC multipliers "
             "(xsim cycles, Vivado post-route Fmax)", x=0.01, ha="left", fontsize=11, color=MUTED)
fig.tight_layout()
fig.savefig(ROOT / "results/exec_time.png", dpi=160, facecolor=SURFACE)
print("wrote results/exec_time.png")
