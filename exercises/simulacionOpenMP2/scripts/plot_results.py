#!/usr/bin/env python3
"""Genera graficas de tiempo y speedup a partir de results/results.csv."""
import csv
import sys
from pathlib import Path
import matplotlib.pyplot as plt

ROOT = Path(__file__).parent.parent
CSV_PATH = ROOT / "results" / "results.csv"

def load():
    rows = list(csv.DictReader(open(CSV_PATH)))
    for r in rows:
        r["threads"] = int(r["threads"])
        r["time"] = float(r["time"])
    seq_time = next(r["time"] for r in rows if r["mode"] == "seq")
    by_mode = {"pfor": [], "sections": []}
    for r in rows:
        if r["mode"] in by_mode:
            by_mode[r["mode"]].append(r)
    for m in by_mode:
        by_mode[m].sort(key=lambda r: r["threads"])
    return seq_time, by_mode

def plot_times(seq_time, by_mode):
    fig, ax = plt.subplots(figsize=(7, 5))
    ax.axhline(seq_time, color="#888", linestyle="--", label=f"Secuencial ({seq_time:.4f}s)")
    for mode, style, label in [("pfor", "o-", "parallel for"), ("sections", "s-", "sections")]:
        rows = by_mode[mode]
        if rows:
            ax.plot([r["threads"] for r in rows], [r["time"] for r in rows], style, label=label)
    ax.set_xlabel("Threads")
    ax.set_ylabel("Tiempo (s)")
    ax.set_title("Tiempo de ejecución: secuencial vs paralelo")
    ax.legend()
    ax.grid(alpha=.3)
    fig.tight_layout()
    fig.savefig(ROOT / "results" / "tiempos.png", dpi=150)

def plot_speedup(seq_time, by_mode):
    fig, ax = plt.subplots(figsize=(7, 5))
    max_t = max((r["threads"] for rows in by_mode.values() for r in rows), default=8)
    ax.plot([1, max_t], [1, max_t], "--", color="#888", label="Speedup ideal")
    for mode, style, label in [("pfor", "o-", "parallel for"), ("sections", "s-", "sections")]:
        rows = by_mode[mode]
        if rows:
            speedup = [seq_time / r["time"] for r in rows]
            ax.plot([r["threads"] for r in rows], speedup, style, label=label)
    ax.set_xlabel("Threads (p)")
    ax.set_ylabel("Speedup (Sp = Ts / Tp)")
    ax.set_title("Curva de Speedup")
    ax.legend()
    ax.grid(alpha=.3)
    fig.tight_layout()
    fig.savefig(ROOT / "results" / "speedup.png", dpi=150)

if __name__ == "__main__":
    if not CSV_PATH.exists():
        sys.exit(f"No existe {CSV_PATH}. Corre ./run_benchmark.sh primero.")
    seq_time, by_mode = load()
    plot_times(seq_time, by_mode)
    plot_speedup(seq_time, by_mode)
    print("Graficas guardadas en results/tiempos.png y results/speedup.png")
