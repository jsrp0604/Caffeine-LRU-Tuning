#!/usr/bin/env python3
"""
generate_graphs.py

For every {trace}_sample{N}.csv found in simulator/build/reports/{trace}/csv/,
generates two graphs (written to simulator/build/reports/{trace}/graphs/) that
correctly space the x-axis by actual cache size:

  {trace}_sample{N}_linear.png  — linear x-axis  (true distance between sizes)
  {trace}_sample{N}_log.png     — log-scale x-axis

Run from the Caffeine project root:
    python scripts/generate_graphs.py

Requirements:  pip install matplotlib
"""

import csv
import math
import re
from pathlib import Path

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from matplotlib.lines import Line2D
from matplotlib.patches import Patch

# ── Configuration ─────────────────────────────────────────────────────────────
# Adjust these if you move files or want different output settings.

REPORTS_DIR = Path(__file__).parent.parent / "simulator" / "build" / "reports"

# Subdirectories inside REPORTS_DIR to skip entirely
SKIP_DIRS = {"simulate"}

# Skip directories whose name ends with this suffix (stale/old runs)
SKIP_SUFFIX = "_old"

# DPI for saved images (150 gives good quality without huge file sizes)
OUTPUT_DPI = 150

# Visual style per policy name.
# Add or edit entries here to control colors, markers, and legend labels.
# Any policy not listed falls back to auto-styled gray.
POLICY_STYLE: dict[str, dict] = {
    "linked.Lru": {
        "label": "linked.LRU",
        "color": "#ad2307",   # blue
        "linestyle": "-",
        "marker": "o",
        "markersize": 3,
        "linewidth": 1.2,
    },
    "sampled.sampled.Lru": {
        "label": "sampled.LRU",
        "color": "#218F08",   # orange
        "linestyle": "--",
        "marker": "s",
        "markersize": 3,
        "linewidth": 1.2,
    }
}

# Sample sizes compared in the per-trace throughput-by-sample bar chart, and the
# policy row (from the {trace}_sample{N}_throughput.csv files) that feeds it.
BAR_SAMPLE_SIZES = [1, 3, 5, 7, 10]
BAR_POLICY = "sampled.sampled.Lru"

# Ordinal blue ramp, light -> dark, one step per entry in BAR_SAMPLE_SIZES
# (sample size is an ordered quantity, so a single-hue sequential ramp is used
# instead of unrelated categorical colors).
BAR_RAMP = ["#86b6ef", "#5598e7", "#2a78d6", "#1c5cab", "#104281"]

# Reference policy (deterministic, no sample-size dependence) overlaid as a
# marker alongside each box in the hit-rate box plot.
BOX_REFERENCE_POLICY = "linked.Lru"

# Trace directories to also render a log-scale miss-rate graph for, in
# addition to the standard hit-rate graphs (mirrors the *_log.png hit-rate
# graph, but plots 100 - hit rate).
MISS_RATE_TRACES = {"msr_web", "msr_src1"}

# Sample (k) sizes overlaid together in the combined miss-rate graph, one line
# per k plus a linked.Lru reference line.
COMBINED_SAMPLE_SIZES = [1, 2, 4, 8, 10]

# Distinct categorical hues (not a single-hue ramp) for the k lines in the
# combined miss-rate graph — a sequential ramp reads as near-identical shades
# when 5+ lines overlap, so each k gets its own hue plus its own marker shape.
COMBINED_COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4"]
COMBINED_MARKERS = ["s", "^", "D", "v", "P"]

# ── CSV parsing ───────────────────────────────────────────────────────────────

# Matches combined-per-sample files only, not per-size files:
#   meta_kv_sample3.csv          ✓  (what we want)
#   meta_kv_sample3_size52.csv   ✗  (per-size detail, skip)
_SAMPLE_RE     = re.compile(r"^(.+)_sample(\d+)\.csv$")
_THROUGHPUT_RE = re.compile(r"^(.+)_sample(\d+)_throughput\.csv$")
_EAT_RE        = re.compile(r"^(.+)_sample(\d+)_eat_(fast|slow)\.csv$")


def _parse_size(token: str) -> int:
    """Convert a CSV header token like '5,246' or '5_246' to integer 5246."""
    return int(token.replace(",", "").replace("_", ""))


def load_csv(path: Path) -> tuple[list[int], list[dict]]:
    """
    Parse a Caffeine simulator hit-rate CSV.

    Returns:
        sizes  — list of integer cache sizes from the header row
        rows   — list of {"policy": str, "values": list[float]}
    """
    with path.open(newline="") as fh:
        reader = csv.reader(fh)
        header = next(reader)
        sizes = [_parse_size(col) for col in header[1:]]
        rows = []
        for row in reader:
            if not row:
                continue
            rows.append({
                "policy": row[0],
                "values": [float(v) for v in row[1:]],
            })
    return sizes, rows


# ── Plotting ──────────────────────────────────────────────────────────────────

def _si_fmt(x, _):
    """Compact SI formatter: 1340381 → '1.34M', 52460 → '52.5K', 524 → '524'."""
    x = int(round(x))
    if x >= 1_000_000:
        return f"{x / 1_000_000:.3g}M"
    if x >= 1_000:
        return f"{x / 1_000:.3g}K"
    return str(x)


def _fallback_style(policy_name: str) -> dict:
    """Auto-style for policies not listed in POLICY_STYLE."""
    return {
        "label": policy_name,
        "color": "#888888",
        "linestyle": "-.",
        "marker": "x",
        "markersize": 3,
        "linewidth": 1.0,
    }


def _hide_crowded_xlabels(ax, sizes, fig_width_in=11.0, dpi=OUTPUT_DPI, min_gap_px=30):
    """
    Hide x tick labels whose estimated pixel positions are too close to read.
    Works for both "linear" and "log" x-scales.

    For log scale the crowding check is done in log10-space so that distances
    reflect how the axis is actually laid out on screen.

    Greedy left-to-right pass: a label is kept only when it falls at least
    min_gap_px from the most recently kept label.
    """
    if len(sizes) <= 2:
        return

    # Estimate usable plot-area width: 11" × 150 DPI × 0.84 (tight-layout fraction).
    plot_px = fig_width_in * dpi * 0.84

    if ax.get_xscale() == "log":
        coords = [math.log10(s) for s in sizes]
    else:
        coords = [float(s) for s in sizes]

    c_min, c_max = coords[0], coords[-1]
    c_range = c_max - c_min

    def to_px(c: float) -> float:
        return plot_px * (c - c_min) / c_range

    labels = ax.get_xticklabels()
    last_px = -float("inf")

    for label, c in zip(labels, coords):
        px = to_px(c)
        if px - last_px >= min_gap_px:
            last_px = px
        else:
            label.set_visible(False)


def plot_graph(
    sizes: list[int],
    rows: list[dict],
    title: str,
    xscale: str,        # "linear" or "log"
) -> plt.Figure:
    fig, ax = plt.subplots(figsize=(11, 6))

    for row in rows:
        style = POLICY_STYLE.get(row["policy"]) or _fallback_style(row["policy"])
        ax.plot(sizes, row["values"], **style)

    # Scale must be set before placing ticks so log-scale math is correct
    ax.set_xscale(xscale)

    # Pin ticks exactly at the data points (same positions on both scales)
    ax.set_xticks(sizes)
    ax.xaxis.set_major_formatter(mticker.FuncFormatter(_si_fmt))
    if xscale == "log":
        # Suppress auto-added minor ticks that would clutter the log axis
        ax.xaxis.set_minor_locator(mticker.NullLocator())

    # 90-degree rotation: labels are vertical so they need zero horizontal clearance,
    # which handles dense clusters (e.g. 8 million-scale sizes on the twitter log graph).
    plt.setp(ax.get_xticklabels(), rotation=90, ha="center", fontsize=9)

    min_gap = 20 
    _hide_crowded_xlabels(ax, sizes, min_gap_px=min_gap)

    ax.set_xlabel("Cache Size (entries)", fontsize=12)
    ax.set_ylabel("Hit Rate (%)", fontsize=12)
    ax.yaxis.set_major_locator(mticker.MultipleLocator(10))
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda y, _: f"{y:.0f}%"))
    ax.set_ylim(bottom=0, top=105)

    ax.set_title(title, fontsize=13, pad=10)
    ax.legend(fontsize=11, loc="lower right")

    ax.grid(True, which="major", linestyle="--", alpha=0.5)
    if xscale == "log":
        ax.grid(True, which="minor", linestyle=":", alpha=0.25)

    fig.tight_layout()
    return fig


def plot_missrate_graph(
    sizes: list[int],
    rows: list[dict],
    title: str,
) -> plt.Figure:
    """Log-scale miss-rate graph: same layout/styling as plot_graph's log
    variant, but plots (100 - hit rate) with a "Miss Rate (%)" y-axis."""
    fig, ax = plt.subplots(figsize=(11, 6))

    for row in rows:
        style = POLICY_STYLE.get(row["policy"]) or _fallback_style(row["policy"])
        ax.plot(sizes, [100.0 - v for v in row["values"]], **style)

    ax.set_xscale("log")
    ax.set_xticks(sizes)
    ax.xaxis.set_major_formatter(mticker.FuncFormatter(_si_fmt))
    ax.xaxis.set_minor_locator(mticker.NullLocator())

    plt.setp(ax.get_xticklabels(), rotation=90, ha="center", fontsize=9)
    _hide_crowded_xlabels(ax, sizes, min_gap_px=20)

    ax.set_xlabel("Cache Size (entries)", fontsize=12)
    ax.set_ylabel("Miss Rate (%)", fontsize=12)
    ax.yaxis.set_major_locator(mticker.MultipleLocator(10))
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda y, _: f"{y:.0f}%"))
    ax.set_ylim(bottom=0, top=105)

    ax.set_title(title, fontsize=13, pad=10)
    ax.legend(fontsize=11, loc="upper right")

    ax.grid(True, which="major", linestyle="--", alpha=0.5)
    ax.grid(True, which="minor", linestyle=":", alpha=0.25)

    fig.tight_layout()
    return fig


def plot_combined_missrate_graph(
    sizes: list[int],
    per_k_values: dict[int, list[float]],
    reference_values: list[float],
    title: str,
) -> plt.Figure:
    """Log-scale miss-rate graph overlaying sampled.Lru at each k in
    COMBINED_SAMPLE_SIZES (light -> dark ramp) plus linked.Lru as a reference
    line, all on one set of axes."""
    fig, ax = plt.subplots(figsize=(11, 6))

    for i, k in enumerate(COMBINED_SAMPLE_SIZES):
        ax.plot(
            sizes,
            [100.0 - v for v in per_k_values[k]],
            color=COMBINED_COLORS[i],
            linestyle="--",
            marker=COMBINED_MARKERS[i],
            markersize=4,
            linewidth=1.2,
            label=f"sampled.LRU (k={k})",
        )

    reference_style = POLICY_STYLE[BOX_REFERENCE_POLICY]
    ax.plot(
        sizes,
        [100.0 - v for v in reference_values],
        color=reference_style["color"],
        linestyle="-",
        marker="o",
        markersize=3,
        linewidth=1.2,
        label=reference_style["label"],
    )

    ax.set_xscale("log")
    ax.set_xticks(sizes)
    ax.xaxis.set_major_formatter(mticker.FuncFormatter(_si_fmt))
    ax.xaxis.set_minor_locator(mticker.NullLocator())

    plt.setp(ax.get_xticklabels(), rotation=90, ha="center", fontsize=9)
    _hide_crowded_xlabels(ax, sizes, min_gap_px=20)

    ax.set_xlabel("Cache Size (entries)", fontsize=12)
    ax.set_ylabel("Miss Rate (%)", fontsize=12)
    ax.yaxis.set_major_locator(mticker.MultipleLocator(10))
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda y, _: f"{y:.0f}%"))
    ax.set_ylim(bottom=0, top=105)

    ax.set_title(title, fontsize=13, pad=10)
    ax.legend(fontsize=10, loc="upper right")

    ax.grid(True, which="major", linestyle="--", alpha=0.5)
    ax.grid(True, which="minor", linestyle=":", alpha=0.25)

    fig.tight_layout()
    return fig


# ── Throughput graph ──────────────────────────────────────────────────────────

def plot_throughput_graph(sizes: list[int], rows: list[dict], title: str) -> plt.Figure:
    fig, ax = plt.subplots(figsize=(11, 6))

    for row in rows:
        style = POLICY_STYLE.get(row["policy"]) or _fallback_style(row["policy"])
        ax.plot(sizes, row["values"], **style)

    ax.set_xscale("log")
    ax.set_xticks(sizes)
    ax.xaxis.set_major_formatter(mticker.FuncFormatter(_si_fmt))
    ax.xaxis.set_minor_locator(mticker.NullLocator())
    plt.setp(ax.get_xticklabels(), rotation=90, ha="center", fontsize=9)
    _hide_crowded_xlabels(ax, sizes, min_gap_px=20)

    ax.set_xlabel("Cache Size (entries)", fontsize=12)
    ax.set_ylabel("Throughput (req/ms)", fontsize=12)

    ax.set_title(title, fontsize=13, pad=10)
    ax.legend(fontsize=11, loc="upper right")

    ax.grid(True, which="major", linestyle="--", alpha=0.5)
    ax.grid(True, which="minor", linestyle=":", alpha=0.25)

    fig.tight_layout()
    return fig


def plot_eat_graph(sizes: list[int], rows: list[dict], title: str) -> plt.Figure:
    fig, ax = plt.subplots(figsize=(11, 6))

    for row in rows:
        style = POLICY_STYLE.get(row["policy"]) or _fallback_style(row["policy"])
        ax.plot(sizes, row["values"], **style)

    ax.set_xscale("log")
    ax.set_xticks(sizes)
    ax.xaxis.set_major_formatter(mticker.FuncFormatter(_si_fmt))
    ax.xaxis.set_minor_locator(mticker.NullLocator())
    plt.setp(ax.get_xticklabels(), rotation=90, ha="center", fontsize=9)
    _hide_crowded_xlabels(ax, sizes, min_gap_px=20)

    ax.set_xlabel("Cache Size (entries)", fontsize=12)
    ax.set_ylabel("Effective Access Time (ms)", fontsize=12)

    ax.set_title(title, fontsize=13, pad=10)
    ax.legend(fontsize=11, loc="upper right")

    ax.grid(True, which="major", linestyle="--", alpha=0.5)
    ax.grid(True, which="minor", linestyle=":", alpha=0.25)

    fig.tight_layout()
    return fig


def plot_throughput_bar_chart(
    sizes: list[int],
    sample_values: dict[int, list[float]],
    title: str,
) -> plt.Figure:
    """
    Grouped bar chart: one group per cache size, one bar per sample size in
    BAR_SAMPLE_SIZES, comparing sampled.Lru's throughput across sample sizes.
    """
    n_groups = len(sizes)
    n_bars = len(BAR_SAMPLE_SIZES)
    fig_width = max(14.0, n_groups * 1.1)
    fig, ax = plt.subplots(figsize=(fig_width, 6))

    group_width = 0.82
    bar_width = group_width / n_bars
    x = list(range(n_groups))

    for i, sample_n in enumerate(BAR_SAMPLE_SIZES):
        offset = (i - (n_bars - 1) / 2) * bar_width
        positions = [xi + offset for xi in x]
        ax.bar(
            positions,
            sample_values[sample_n],
            width=bar_width * 0.9,
            color=BAR_RAMP[i],
            edgecolor="white",
            linewidth=0.4,
            label=f"Sample Size {sample_n}",
        )

    ax.set_xticks(x)
    ax.set_xticklabels([_si_fmt(s, None) for s in sizes], rotation=90, ha="center", fontsize=9)

    ax.set_xlabel("Cache Size (entries)", fontsize=12)
    ax.set_ylabel("Throughput (req/ms)", fontsize=12)
    ax.set_title(title, fontsize=13, pad=10)
    ax.legend(fontsize=10, loc="upper right", ncol=n_bars, frameon=False)

    ax.set_axisbelow(True)
    ax.grid(True, axis="y", which="major", linestyle="--", alpha=0.5)

    fig.tight_layout()
    return fig


def plot_hitrate_boxplot(
    sizes: list[int],
    box_values: list[list[float]],
    reference_values: list[float],
    title: str,
) -> plt.Figure:
    """
    Box plot: one box per cache size, showing the spread of sampled.Lru's hit
    rate across BAR_SAMPLE_SIZES at that size. linked.Lru's hit rate (identical
    regardless of sample size) is overlaid as a reference diamond marker.
    """
    n_groups = len(sizes)
    fig_width = max(14.0, n_groups * 1.1)
    fig, ax = plt.subplots(figsize=(fig_width, 6))

    sampled_style = POLICY_STYLE[BAR_POLICY]
    reference_style = POLICY_STYLE[BOX_REFERENCE_POLICY]

    x = list(range(1, n_groups + 1))
    ax.boxplot(
        box_values,
        positions=x,
        widths=0.5,
        patch_artist=True,
        whis=(0, 100),  # whiskers span true min/max: with only 5 points per
                        # box, every value is meaningful, not a statistical outlier
        boxprops={
            "facecolor": sampled_style["color"],
            "alpha": 0.35,
            "edgecolor": sampled_style["color"],
        },
        medianprops={"color": sampled_style["color"], "linewidth": 1.5},
        whiskerprops={"color": sampled_style["color"]},
        capprops={"color": sampled_style["color"]},
    )

    ax.plot(
        x,
        reference_values,
        linestyle="none",
        marker="D",
        markersize=6,
        color=reference_style["color"],
        zorder=5,
    )

    ax.set_xticks(x)
    ax.set_xticklabels([_si_fmt(s, None) for s in sizes], rotation=90, ha="center", fontsize=9)

    ax.set_xlabel("Cache Size (entries)", fontsize=12)
    ax.set_ylabel("Hit Rate (%)", fontsize=12)
    ax.yaxis.set_major_locator(mticker.MultipleLocator(10))
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda y, _: f"{y:.0f}%"))
    ax.set_ylim(bottom=0, top=105)

    ax.set_title(title, fontsize=13, pad=10)

    sample_list = ", ".join(str(n) for n in BAR_SAMPLE_SIZES)
    box_proxy = Patch(
        facecolor=sampled_style["color"], alpha=0.35, edgecolor=sampled_style["color"],
        label=f"sampled.LRU (sample sizes {sample_list})",
    )
    ref_proxy = Line2D(
        [0], [0], marker="D", linestyle="none", markersize=6,
        color=reference_style["color"], label="linked.LRU (reference)",
    )
    ax.legend(handles=[box_proxy, ref_proxy], fontsize=10, loc="lower right")

    ax.set_axisbelow(True)
    ax.grid(True, axis="y", which="major", linestyle="--", alpha=0.5)

    fig.tight_layout()
    return fig


def plot_hitrate_delta_boxplot(
    sizes: list[int],
    box_deltas: list[list[float]],
    title: str,
) -> plt.Figure:
    """
    Zoomed companion to plot_hitrate_boxplot: same one-box-per-cache-size
    layout, but plots (sampled.Lru - linked.Lru) in percentage points instead
    of absolute hit rate. This removes the 8%-85% swing in absolute hit rate
    across cache sizes that otherwise dwarfs the few-point sample-size spread,
    so the y-axis auto-scales tightly around the actual differences.
    linked.Lru becomes the flat y=0 reference line rather than a per-size marker.
    """
    n_groups = len(sizes)
    fig_width = max(14.0, n_groups * 1.1)
    fig, ax = plt.subplots(figsize=(fig_width, 6))

    sampled_style = POLICY_STYLE[BAR_POLICY]
    reference_style = POLICY_STYLE[BOX_REFERENCE_POLICY]

    x = list(range(1, n_groups + 1))
    ax.boxplot(
        box_deltas,
        positions=x,
        widths=0.5,
        patch_artist=True,
        whis=(0, 100),  # whiskers span true min/max: with only 5 points per
                        # box, every value is meaningful, not a statistical outlier
        boxprops={
            "facecolor": sampled_style["color"],
            "alpha": 0.35,
            "edgecolor": sampled_style["color"],
        },
        medianprops={"color": sampled_style["color"], "linewidth": 1.5},
        whiskerprops={"color": sampled_style["color"]},
        capprops={"color": sampled_style["color"]},
    )

    ax.axhline(0, color=reference_style["color"], linewidth=1.5, zorder=5)

    ax.set_xticks(x)
    ax.set_xticklabels([_si_fmt(s, None) for s in sizes], rotation=90, ha="center", fontsize=9)

    ax.set_xlabel("Cache Size (entries)", fontsize=12)
    ax.set_ylabel("Hit Rate Δ vs linked.LRU (pp)", fontsize=12)
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda y, _: f"{y:+.1f}pp"))

    ax.set_title(title, fontsize=13, pad=10)

    sample_list = ", ".join(str(n) for n in BAR_SAMPLE_SIZES)
    box_proxy = Patch(
        facecolor=sampled_style["color"], alpha=0.35, edgecolor=sampled_style["color"],
        label=f"sampled.LRU − linked.LRU (sample sizes {sample_list})",
    )
    ref_proxy = Line2D(
        [0], [0], color=reference_style["color"], linewidth=1.5,
        label="linked.LRU (baseline, Δ=0)",
    )
    ax.legend(handles=[box_proxy, ref_proxy], fontsize=10, loc="lower right")

    ax.set_axisbelow(True)
    ax.grid(True, axis="y", which="major", linestyle="--", alpha=0.5)

    fig.tight_layout()
    return fig


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    if not REPORTS_DIR.exists():
        print(f"[ERROR] Reports directory not found:\n  {REPORTS_DIR}")
        print("  Run the simulation scripts first, or update REPORTS_DIR at the top of this file.")
        return

    total = 0

    for trace_dir in sorted(REPORTS_DIR.iterdir()):
        if not trace_dir.is_dir():
            continue
        if trace_dir.name in SKIP_DIRS or trace_dir.name.endswith(SKIP_SUFFIX):
            continue

        csv_dir = trace_dir / "csv"
        graphs_dir = trace_dir / "graphs"
        graphs_dir.mkdir(exist_ok=True)

        # Collect only the combined-per-sample CSVs for this trace directory
        candidates: list[tuple[int, str, Path]] = []
        for csv_path in sorted(csv_dir.glob("*.csv")):
            m = _SAMPLE_RE.match(csv_path.name)
            if m:
                candidates.append((int(m.group(2)), m.group(1), csv_path))

        if not candidates:
            continue

        print(f"\n{'-' * 58}")
        print(f"  {trace_dir.name}  ({len(candidates)} sample CSVs)")
        print(f"{'-' * 58}")

        for sample_n, trace_name, csv_path in sorted(candidates):
            sizes, rows = load_csv(csv_path)

            # Title: "Meta Kv Sample1 — Linear scale" etc.
            pretty_name = trace_name.replace("_", " ").title()
            base_title = f"{pretty_name} — Sample Size {sample_n}"

            for xscale, suffix, scale_label in [
                ("linear", "linear", "Linear scale"),
                ("log",    "log",    "Log scale"),
            ]:
                fig = plot_graph(sizes, rows, f"{base_title} ({scale_label})", xscale)
                out = graphs_dir / f"{csv_path.stem}_{suffix}.png"
                fig.savefig(out, dpi=OUTPUT_DPI, bbox_inches="tight")
                plt.close(fig)
                print(f"    OK  {out.name}")
                total += 1

            if trace_dir.name in MISS_RATE_TRACES:
                fig = plot_missrate_graph(sizes, rows, f"{base_title} (Log scale)")
                out = graphs_dir / f"{csv_path.stem}_missrate_log.png"
                fig.savefig(out, dpi=OUTPUT_DPI, bbox_inches="tight")
                plt.close(fig)
                print(f"    OK  {out.name}")
                total += 1

        # Throughput log graphs — one per throughput CSV in this trace directory
        throughput_candidates: list[tuple[int, str, Path]] = []
        for csv_path in sorted(csv_dir.glob("*_throughput.csv")):
            m = _THROUGHPUT_RE.match(csv_path.name)
            if m:
                throughput_candidates.append((int(m.group(2)), m.group(1), csv_path))

        for sample_n, trace_name, csv_path in sorted(throughput_candidates):
            sizes, rows = load_csv(csv_path)
            pretty_name = trace_name.replace("_", " ").title()
            title = f"{pretty_name} — Sample Size {sample_n} — Throughput (Log scale)"
            fig = plot_throughput_graph(sizes, rows, title)
            out = graphs_dir / f"{csv_path.stem}_log.png"
            fig.savefig(out, dpi=OUTPUT_DPI, bbox_inches="tight")
            plt.close(fig)
            print(f"    OK  {out.name}")
            total += 1

        # EAT (Effective Access Time) graphs — one per backend instance
        # (fast/slow) per sample, log-scale cache-size x-axis.
        eat_candidates: list[tuple[int, str, str, Path]] = []
        for csv_path in sorted(csv_dir.glob("*_eat_*.csv")):
            m = _EAT_RE.match(csv_path.name)
            if m:
                eat_candidates.append((int(m.group(2)), m.group(1), m.group(3), csv_path))

        for sample_n, trace_name, backend, csv_path in sorted(eat_candidates):
            sizes, rows = load_csv(csv_path)
            pretty_name = trace_name.replace("_", " ").title()
            title = (f"{pretty_name} — Sample Size {sample_n} — "
                      f"Effective Access Time ({backend.title()} Backend, Log scale)")
            fig = plot_eat_graph(sizes, rows, title)
            out = graphs_dir / f"{csv_path.stem}_log.png"
            fig.savefig(out, dpi=OUTPUT_DPI, bbox_inches="tight")
            plt.close(fig)
            print(f"    OK  {out.name}")
            total += 1

        # Throughput-by-sample-size bar chart — one per trace, comparing
        # sampled.Lru across BAR_SAMPLE_SIZES at each cache size.
        throughput_by_sample: dict[int, Path] = {
            sample_n: csv_path for sample_n, _, csv_path in throughput_candidates
        }
        if all(n in throughput_by_sample for n in BAR_SAMPLE_SIZES):
            sizes_ref: list[int] | None = None
            sample_values: dict[int, list[float]] = {}
            ok = True
            for sample_n in BAR_SAMPLE_SIZES:
                sizes, rows = load_csv(throughput_by_sample[sample_n])
                if sizes_ref is None:
                    sizes_ref = sizes
                elif sizes != sizes_ref:
                    print(f"    SKIP throughput-by-sample bar chart: cache sizes "
                          f"differ between sample{sample_n} and earlier samples")
                    ok = False
                    break
                policy_row = next((r for r in rows if r["policy"] == BAR_POLICY), None)
                if policy_row is None:
                    print(f"    SKIP throughput-by-sample bar chart: '{BAR_POLICY}' "
                          f"not found in sample{sample_n} throughput CSV")
                    ok = False
                    break
                sample_values[sample_n] = policy_row["values"]

            if ok:
                pretty_name = trace_dir.name.replace("_", " ").title()
                title = f"{pretty_name} — sampled.LRU Throughput by Sample Size"
                fig = plot_throughput_bar_chart(sizes_ref, sample_values, title)
                out = graphs_dir / f"{trace_dir.name}_throughput_bysample.png"
                fig.savefig(out, dpi=OUTPUT_DPI, bbox_inches="tight")
                plt.close(fig)
                print(f"    OK  {out.name}")
                total += 1

        # Hit-rate box plot — one per trace: box per cache size showing the
        # spread of sampled.Lru's hit rate across BAR_SAMPLE_SIZES, with
        # linked.Lru overlaid as a reference marker.
        hitrate_by_sample: dict[int, Path] = {
            sample_n: csv_path for sample_n, _, csv_path in candidates
        }
        if all(n in hitrate_by_sample for n in BAR_SAMPLE_SIZES):
            sizes_ref = None
            per_sample_values: dict[int, list[float]] = {}
            reference_values: list[float] | None = None
            ok = True
            for sample_n in BAR_SAMPLE_SIZES:
                sizes, rows = load_csv(hitrate_by_sample[sample_n])
                if sizes_ref is None:
                    sizes_ref = sizes
                elif sizes != sizes_ref:
                    print(f"    SKIP hit-rate box plot: cache sizes differ "
                          f"between sample{sample_n} and earlier samples")
                    ok = False
                    break
                sampled_row = next((r for r in rows if r["policy"] == BAR_POLICY), None)
                reference_row = next((r for r in rows if r["policy"] == BOX_REFERENCE_POLICY), None)
                if sampled_row is None or reference_row is None:
                    print(f"    SKIP hit-rate box plot: missing '{BAR_POLICY}' or "
                          f"'{BOX_REFERENCE_POLICY}' in sample{sample_n} CSV")
                    ok = False
                    break
                per_sample_values[sample_n] = sampled_row["values"]
                if reference_values is None:
                    reference_values = reference_row["values"]

            if ok:
                box_values = [
                    [per_sample_values[n][i] for n in BAR_SAMPLE_SIZES]
                    for i in range(len(sizes_ref))
                ]
                pretty_name = trace_dir.name.replace("_", " ").title()
                title = f"{pretty_name} — sampled.LRU Hit Rate Distribution vs linked.LRU"
                fig = plot_hitrate_boxplot(sizes_ref, box_values, reference_values, title)
                out = graphs_dir / f"{trace_dir.name}_hitrate_boxplot.png"
                fig.savefig(out, dpi=OUTPUT_DPI, bbox_inches="tight")
                plt.close(fig)
                print(f"    OK  {out.name}")
                total += 1

                # Zoomed companion: same boxes, plotted as delta vs linked.Lru
                # (percentage points) so the y-axis isn't dominated by the
                # 8%-85% swing in absolute hit rate across cache sizes.
                box_deltas = [
                    [per_sample_values[n][i] - reference_values[i] for n in BAR_SAMPLE_SIZES]
                    for i in range(len(sizes_ref))
                ]
                delta_title = f"{pretty_name} — sampled.LRU Hit Rate Delta vs linked.LRU (Zoomed)"
                delta_fig = plot_hitrate_delta_boxplot(sizes_ref, box_deltas, delta_title)
                delta_out = graphs_dir / f"{trace_dir.name}_hitrate_delta_boxplot.png"
                delta_fig.savefig(delta_out, dpi=OUTPUT_DPI, bbox_inches="tight")
                plt.close(delta_fig)
                print(f"    OK  {delta_out.name}")
                total += 1

        # Combined miss-rate graph — one per trace: sampled.Lru at each k in
        # COMBINED_SAMPLE_SIZES overlaid with linked.Lru, all on one graph.
        if trace_dir.name in MISS_RATE_TRACES and all(
            k in hitrate_by_sample for k in COMBINED_SAMPLE_SIZES
        ):
            sizes_ref = None
            per_k_values: dict[int, list[float]] = {}
            reference_values = None
            ok = True
            for k in COMBINED_SAMPLE_SIZES:
                sizes, rows = load_csv(hitrate_by_sample[k])
                if sizes_ref is None:
                    sizes_ref = sizes
                elif sizes != sizes_ref:
                    print(f"    SKIP combined miss-rate graph: cache sizes differ "
                          f"between sample{k} and earlier samples")
                    ok = False
                    break
                sampled_row = next((r for r in rows if r["policy"] == BAR_POLICY), None)
                reference_row = next((r for r in rows if r["policy"] == BOX_REFERENCE_POLICY), None)
                if sampled_row is None or reference_row is None:
                    print(f"    SKIP combined miss-rate graph: missing '{BAR_POLICY}' or "
                          f"'{BOX_REFERENCE_POLICY}' in sample{k} CSV")
                    ok = False
                    break
                per_k_values[k] = sampled_row["values"]
                if reference_values is None:
                    reference_values = reference_row["values"]

            if ok:
                pretty_name = trace_dir.name.replace("_", " ").title()
                k_list = ", ".join(str(k) for k in COMBINED_SAMPLE_SIZES)
                title = f"{pretty_name} — Miss Rate: sampled.LRU (k={k_list}) vs linked.LRU (Log scale)"
                fig = plot_combined_missrate_graph(sizes_ref, per_k_values, reference_values, title)
                out = graphs_dir / f"{trace_dir.name}_missrate_combined_log.png"
                fig.savefig(out, dpi=OUTPUT_DPI, bbox_inches="tight")
                plt.close(fig)
                print(f"    OK  {out.name}")
                total += 1

    print(f"\n{'=' * 58}")
    print(f"  Done.  {total} graphs generated.")
    print("=" * 58)


if __name__ == "__main__":
    main()
