#!/usr/bin/env python3
"""
plot_comparison.py — Side-by-side WRF run comparison
=====================================================
Produces a two-panel figure comparing two WRF runs on the same grid.
Each panel shows:
  • 2-m Temperature  — colour shading  (°C)
  • Surface pressure — contour lines   (hPa)
  • 10-m wind        — barbs

Both panels share the same temperature colour scale so differences are
immediately visible.

Usage
-----
    # From the Exercise 3 working directory:
    python3 $HOME/WRF_demo/exercises/03_sensitivity_run/plot_comparison.py \\
        --run1  $HOME/WRF_demo_env/run/ex01 \\
        --run2  $HOME/WRF_demo_env/run/ex03 \\
        --label1 "Ex01 CONUS suite" \\
        --label2 "Ex03 KF/RRTMG/YSU" \\
        --time 6

Arguments
---------
    --run1      Directory containing the first set of wrfout files  (default: ../ex01)
    --run2      Directory containing the second set of wrfout files (default: .)
    --label1    Title label for the left panel  (default: "Run 1")
    --label2    Title label for the right panel (default: "Run 2")
    --time  N   Time index within the wrfout file (0 = analysis time, default: 0)
    --out FILE  Output PNG filename (default: auto-generated)

Output
------
    comparison_<label2>_t<N>.png  saved in the current directory.
"""

import argparse
import glob
import os
import sys

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import netCDF4 as nc

try:
    import cartopy.crs as ccrs
    import cartopy.feature as cfeature
    HAS_CARTOPY = True
except ImportError:
    HAS_CARTOPY = False
    print("NOTE: cartopy not available — plotting without map projection.")

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
parser = argparse.ArgumentParser(
    description="Side-by-side comparison of two WRF runs."
)
parser.add_argument("--run1",   default=None,
                    help="Directory with wrfout files for Run 1 (default: $BASE_DIR/run/ex01)")
parser.add_argument("--run2",   default=".",
                    help="Directory with wrfout files for Run 2 (default: current directory)")
parser.add_argument("--label1", default="Run 1 — Ex01 CONUS suite",
                    help="Panel title for Run 1")
parser.add_argument("--label2", default="Run 2 — Ex03 sensitivity",
                    help="Panel title for Run 2")
parser.add_argument("--time", "-t", type=int, default=0, metavar="N",
                    help="Time index to plot (default: 0)")
parser.add_argument("--out", "-o", default=None,
                    help="Output PNG path (default: auto)")
args = parser.parse_args()

# Resolve run1 default from environment if not given
if args.run1 is None:
    base = os.environ.get("BASE_DIR", os.path.expanduser("~/WRF_demo_env"))
    args.run1 = os.path.join(base, "run", "ex01")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def find_wrfout(directory):
    """Return the first wrfout_d01_* file found in directory."""
    candidates = sorted(glob.glob(os.path.join(directory, "wrfout_d01_*")))
    if not candidates:
        sys.exit(
            f"ERROR: No wrfout_d01_* files found in {directory}\n"
            f"       Make sure wrf.exe has completed successfully."
        )
    return candidates[0]


def read_fields(wrfout_path, tidx):
    """Open a wrfout file and return a dict of 2-D arrays + metadata."""
    ds = nc.Dataset(wrfout_path)

    def get(name, ndim_expected=3):
        v = ds.variables[name]
        if v.ndim == 4:
            return np.array(v[tidx, 0, :, :])
        return np.array(v[tidx, :, :])

    data = {
        "xlat":  np.array(ds.variables["XLAT"][tidx]),
        "xlong": np.array(ds.variables["XLONG"][tidx]),
        "T2":    get("T2")   - 273.15,           # °C
        "PSFC":  get("PSFC") / 100.0,            # hPa
        "U10":   get("U10"),                      # m/s
        "V10":   get("V10"),                      # m/s
        "valid": b"".join(ds.variables["Times"][tidx]).decode().replace("_", " "),
    }
    ds.close()
    return data


def add_features(ax):
    if HAS_CARTOPY:
        ax.add_feature(cfeature.COASTLINE, linewidth=0.8, edgecolor="black")
        ax.add_feature(cfeature.BORDERS,   linewidth=0.4, edgecolor="#555555")
        ax.add_feature(cfeature.STATES,    linewidth=0.3, edgecolor="#888888",
                       linestyle="--")
        g = ax.gridlines(draw_labels=True, linewidth=0.3,
                         color="grey", alpha=0.5, linestyle="--")
        g.top_labels   = False
        g.right_labels = False
        g.xlocator = mticker.MaxNLocator(5)
        g.ylocator = mticker.MaxNLocator(5)

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
path1 = find_wrfout(args.run1)
path2 = find_wrfout(args.run2)
print(f"Run 1: {path1}")
print(f"Run 2: {path2}")

d1 = read_fields(path1, args.time)
d2 = read_fields(path2, args.time)

# ---------------------------------------------------------------------------
# Shared colour scale — span both runs so differences are visible
# ---------------------------------------------------------------------------
t_all  = np.concatenate([d1["T2"].ravel(), d2["T2"].ravel()])
t_min  = np.nanpercentile(t_all, 2)
t_max  = np.nanpercentile(t_all, 98)
t_levs = np.linspace(t_min, t_max, 21)

# Pressure contour levels — rounded to nearest 2 hPa
p_all  = np.concatenate([d1["PSFC"].ravel(), d2["PSFC"].ravel()])
p_min  = np.floor(np.nanmin(p_all) / 2) * 2
p_max  = np.ceil( np.nanmax(p_all) / 2) * 2
p_levs = np.arange(p_min, p_max + 2, 4)   # every 4 hPa

# Wind barb sub-sampling
skip = max(1, d1["xlat"].shape[0] // 18)

# ---------------------------------------------------------------------------
# Figure
# ---------------------------------------------------------------------------
if HAS_CARTOPY:
    proj       = ccrs.PlateCarree()
    subplot_kw = {"projection": proj}
    pkw        = {"transform": ccrs.PlateCarree()}
else:
    subplot_kw = {}
    pkw        = {}

fig, axes = plt.subplots(1, 2, figsize=(18, 7),
                         subplot_kw=subplot_kw,
                         constrained_layout=True)

fig.suptitle(
    f"WRF sensitivity comparison  —  valid: {d1['valid']} UTC"
    f"  (time index {args.time})",
    fontsize=12,
)

for ax, d, label in zip(axes, [d1, d2], [args.label1, args.label2]):

    # Temperature shading
    cf = ax.contourf(d["xlong"], d["xlat"], d["T2"],
                     levels=t_levs, cmap="RdYlBu_r",
                     extend="both", **pkw)

    # Pressure contours
    cs = ax.contour(d["xlong"], d["xlat"], d["PSFC"],
                    levels=p_levs, colors="black",
                    linewidths=0.7, alpha=0.7, **pkw)
    ax.clabel(cs, inline=True, fontsize=7, fmt="%.0f")

    # Wind barbs
    sl = slice(None, None, skip)
    ax.barbs(
        d["xlong"][sl, sl], d["xlat"][sl, sl],
        d["U10"][sl, sl],   d["V10"][sl, sl],
        length=5, linewidth=0.6,
        barb_increments=dict(half=2.5, full=5, flag=25),
        **pkw,
    )

    add_features(ax)
    ax.set_title(label, fontsize=11, pad=6)

# Shared colourbar
cbar = fig.colorbar(cf, ax=axes.ravel().tolist(),
                    orientation="horizontal",
                    shrink=0.6, pad=0.04, aspect=40,
                    label="2-m Temperature (°C)")
cbar.ax.tick_params(labelsize=8)

# ---------------------------------------------------------------------------
# Annotations explaining what is different
# ---------------------------------------------------------------------------
fig.text(
    0.5, 0.01,
    "Shading: 2-m Temperature (°C)   |   Contours: Surface Pressure (hPa, every 4 hPa)"
    "   |   Barbs: 10-m Wind (half barb = 2.5 m/s, full barb = 5 m/s)",
    ha="center", fontsize=8, color="#444444",
)

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
label_slug = args.label2.replace(" ", "_").replace("/", "-")[:30]
out_file = args.out or f"comparison_{label_slug}_t{args.time:02d}.png"
fig.savefig(out_file, dpi=150, bbox_inches="tight")
print(f"Saved: {out_file}")
