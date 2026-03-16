#!/usr/bin/env python3
"""
plot_wrf_output.py — WRF Exercise 1 output visualisation
=========================================================
Reads the first wrfout file it finds in the current directory (or a path
given on the command line) and produces a 3-panel figure showing:

    Panel 1 — 2-m Temperature        (T2, °C)
    Panel 2 — 10-m Wind speed        (U10/V10, m/s)
    Panel 3 — Surface pressure       (PSFC, hPa)

Usage
-----
    # From the WRF run directory (with wrfout files present):
    python3 $HOME/WRF_demo/exercises/01_basic_wrf_run/plot_wrf_output.py

    # Specify a file explicitly:
    python3 plot_wrf_output.py wrfout_d01_2019-09-04_12:00:00

    # Choose a specific time index inside the file (0 = first time step):
    python3 plot_wrf_output.py wrfout_d01_2019-09-04_12:00:00 --time 1

Output
------
    wrf_output_<date>_<hour>UTC.png  saved in the current directory.
"""

import argparse
import glob
import os
import sys

import numpy as np
import matplotlib
matplotlib.use("Agg")           # no display needed
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
# Argument parsing
# ---------------------------------------------------------------------------
parser = argparse.ArgumentParser(description="Plot basic WRF output fields.")
parser.add_argument(
    "wrfout",
    nargs="?",
    default=None,
    help="Path to a wrfout file.  If omitted, the first wrfout_d01_* file "
         "found in the current directory is used.",
)
parser.add_argument(
    "--time", "-t",
    type=int,
    default=0,
    metavar="N",
    help="Time index within the file to plot (default: 0 = first time step).",
)
parser.add_argument(
    "--out", "-o",
    default=None,
    metavar="FILE",
    help="Output PNG filename (default: auto-generated from the valid time).",
)
args = parser.parse_args()

# ---------------------------------------------------------------------------
# Locate the wrfout file
# ---------------------------------------------------------------------------
if args.wrfout:
    wrfout_path = args.wrfout
else:
    candidates = sorted(glob.glob("wrfout_d01_*"))
    if not candidates:
        sys.exit(
            "ERROR: No wrfout_d01_* files found in the current directory.\n"
            "       Run wrf.exe first, or pass the file path as an argument."
        )
    wrfout_path = candidates[0]
    print(f"Using: {wrfout_path}")

if not os.path.isfile(wrfout_path):
    sys.exit(f"ERROR: File not found: {wrfout_path}")

# ---------------------------------------------------------------------------
# Read variables
# ---------------------------------------------------------------------------
ds = nc.Dataset(wrfout_path)

def read_var(name):
    """Read a variable at the chosen time index, squeeze extra dims."""
    var = ds.variables[name]
    if var.ndim == 4:
        return var[args.time, 0, :, :]   # (time, level, y, x)
    elif var.ndim == 3:
        return var[args.time, :, :]       # (time, y, x)
    else:
        return var[:]

# Coordinates
xlat  = read_var("XLAT")   # (y, x)
xlong = read_var("XLONG")  # (y, x)

# Meteorological fields
T2   = read_var("T2")    - 273.15          # K  → °C
U10  = read_var("U10")                      # m/s
V10  = read_var("V10")                      # m/s
WSPD = np.sqrt(U10**2 + V10**2)            # m/s
PSFC = read_var("PSFC")  / 100.0           # Pa → hPa

# Valid time string
times = ds.variables["Times"]
valid_str = b"".join(times[args.time]).decode("utf-8").replace("_", " ")
valid_label = valid_str.replace(":", "").replace(" ", "_")

ds.close()

# ---------------------------------------------------------------------------
# Helper: add common map features (coastlines, borders, grid)
# ---------------------------------------------------------------------------
def add_features(ax, gl=True):
    if HAS_CARTOPY:
        ax.add_feature(cfeature.COASTLINE, linewidth=0.7, edgecolor="black")
        ax.add_feature(cfeature.BORDERS,   linewidth=0.4, edgecolor="grey")
        ax.add_feature(cfeature.STATES,    linewidth=0.3, edgecolor="grey",
                       linestyle="--")
        if gl:
            g = ax.gridlines(draw_labels=True, linewidth=0.3,
                             color="grey", alpha=0.6, linestyle="--")
            g.top_labels   = False
            g.right_labels = False
            g.xlocator = mticker.MaxNLocator(5)
            g.ylocator = mticker.MaxNLocator(5)

# ---------------------------------------------------------------------------
# Build figure
# ---------------------------------------------------------------------------
if HAS_CARTOPY:
    proj = ccrs.PlateCarree()
    subplot_kw = {"projection": proj}
else:
    subplot_kw = {}

fig, axes = plt.subplots(1, 3, figsize=(18, 6),
                         subplot_kw=subplot_kw,
                         constrained_layout=True)
fig.suptitle(f"WRF output  —  valid: {valid_str} UTC", fontsize=13)

plot_kwargs = dict(transform=ccrs.PlateCarree()) if HAS_CARTOPY else {}

# --- Panel 1: 2-m Temperature ---
ax = axes[0]
vmin, vmax = np.nanpercentile(T2, 2), np.nanpercentile(T2, 98)
cf = ax.contourf(xlong, xlat, T2, levels=20,
                 cmap="RdYlBu_r", vmin=vmin, vmax=vmax, **plot_kwargs)
ax.set_title("2-m Temperature (°C)")
add_features(ax)
plt.colorbar(cf, ax=ax, orientation="vertical", shrink=0.85,
             label="°C", pad=0.01)

# --- Panel 2: 10-m Wind speed ---
ax = axes[1]
vmin, vmax = 0, np.nanpercentile(WSPD, 98)
cf = ax.contourf(xlong, xlat, WSPD, levels=20,
                 cmap="YlOrRd", vmin=vmin, vmax=vmax, **plot_kwargs)
ax.set_title("10-m Wind Speed (m/s)")
add_features(ax)
plt.colorbar(cf, ax=ax, orientation="vertical", shrink=0.85,
             label="m/s", pad=0.01)
# Wind barbs (sub-sampled to avoid clutter)
skip = max(1, xlat.shape[0] // 20)
ax.quiver(xlong[::skip, ::skip], xlat[::skip, ::skip],
          U10[::skip, ::skip],   V10[::skip, ::skip],
          scale=300, width=0.003, color="black", **plot_kwargs)

# --- Panel 3: Surface pressure ---
ax = axes[2]
vmin, vmax = np.nanpercentile(PSFC, 2), np.nanpercentile(PSFC, 98)
cf = ax.contourf(xlong, xlat, PSFC, levels=20,
                 cmap="viridis", vmin=vmin, vmax=vmax, **plot_kwargs)
cs = ax.contour(xlong, xlat, PSFC, levels=10,
                colors="white", linewidths=0.5, alpha=0.5, **plot_kwargs)
ax.clabel(cs, inline=True, fontsize=7, fmt="%.0f")
ax.set_title("Surface Pressure (hPa)")
add_features(ax)
plt.colorbar(cf, ax=ax, orientation="vertical", shrink=0.85,
             label="hPa", pad=0.01)

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
out_file = args.out or f"wrf_output_{valid_label}.png"
fig.savefig(out_file, dpi=150, bbox_inches="tight")
print(f"Saved: {out_file}")
