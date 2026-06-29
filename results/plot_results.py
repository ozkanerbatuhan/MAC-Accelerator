#!/usr/bin/env python3
"""
Parse the NEORV32 MAC benchmark log (DATA,N,sw,hw lines), write cycles.csv, and
render speedup.png: cycle counts vs N and speedup vs N.

Usage:
    python plot_results.py --log benchmark_raw.txt --out .
"""
import argparse
import csv
import os
import re

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", default="benchmark_raw.txt")
    ap.add_argument("--out", default=".")
    args = ap.parse_args()

    rows = []
    with open(args.log, "r", encoding="ascii", errors="replace") as f:
        for line in f:
            m = re.match(r"DATA,(\d+),(\d+),(\d+)", line.strip())
            if m:
                n, sw, hw = (int(x) for x in m.groups())
                rows.append((n, sw, hw, sw / hw))
    rows.sort()
    if not rows:
        raise SystemExit("no DATA lines found in log")

    # CSV
    csv_path = os.path.join(args.out, "cycles.csv")
    with open(csv_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["N", "sw_cycles", "hw_cycles", "speedup"])
        for n, sw, hw, sp in rows:
            w.writerow([n, sw, hw, f"{sp:.3f}"])
    print(f"wrote {csv_path}")

    Ns = [r[0] for r in rows]
    sw = [r[1] for r in rows]
    hw = [r[2] for r in rows]
    sp = [r[3] for r in rows]

    plt.rcParams.update({"font.size": 11, "axes.grid": True, "grid.alpha": 0.3})
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4.8))

    # cycles vs N (log-log)
    ax1.plot(Ns, sw, "o-", color="#d9534f", label="Pure software MAC (rv32imc)", linewidth=2)
    ax1.plot(Ns, hw, "s-", color="#5cb85c", label="Custom 'mac' instruction (CFU)", linewidth=2)
    ax1.set_xscale("log", base=2)
    ax1.set_yscale("log", base=2)
    ax1.set_xlabel("Dot-product length N")
    ax1.set_ylabel("Cycle count (rdcycle)")
    ax1.set_title("MAC kernel cycles vs N")
    ax1.set_xticks(Ns); ax1.set_xticklabels(Ns)
    ax1.legend()

    # speedup vs N
    ax2.plot(Ns, sp, "D-", color="#337ab7", linewidth=2)
    for n, s in zip(Ns, sp):
        ax2.annotate(f"{s:.2f}x", (n, s), textcoords="offset points",
                     xytext=(0, 8), ha="center", fontsize=9)
    ax2.axhline(sp[-1], color="gray", linestyle="--", alpha=0.5,
                label=f"asymptote ~{sp[-1]:.2f}x")
    ax2.set_xscale("log", base=2)
    ax2.set_xlabel("Dot-product length N")
    ax2.set_ylabel("Speedup (SW cycles / HW cycles)")
    ax2.set_title("Custom-instruction speedup vs N")
    ax2.set_xticks(Ns); ax2.set_xticklabels(Ns)
    ax2.set_ylim(0, max(sp) * 1.25)
    ax2.legend()

    fig.suptitle("NEORV32 tightly-coupled MAC custom instruction — ZedBoard (Zynq-7020 PL)",
                 fontsize=12, fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.96])
    png_path = os.path.join(args.out, "speedup.png")
    fig.savefig(png_path, dpi=150)
    print(f"wrote {png_path}")


if __name__ == "__main__":
    main()
