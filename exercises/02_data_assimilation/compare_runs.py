#!/usr/bin/env python3
"""
compare_runs.py  —  Print DA-minus-free-forecast difference statistics.

Usage:
    python3 compare_runs.py <ex01_dir> <ex02_dir>

Example:
    python3 compare_runs.py $BASE_DIR/run/ex01 $BASE_DIR/run/ex02
"""

import sys
import glob
import numpy as np
import netCDF4 as nc

if len(sys.argv) != 3:
    sys.exit("Usage: compare_runs.py <ex01_dir> <ex02_dir>")

ex01_dir, ex02_dir = sys.argv[1], sys.argv[2]

files1 = sorted(glob.glob(f"{ex01_dir}/wrfout_d01_*"))
files2 = sorted(glob.glob(f"{ex02_dir}/wrfout_d01_*"))

if not files1:
    sys.exit(f"No wrfout files found in {ex01_dir}")
if not files2:
    sys.exit(f"No wrfout files found in {ex02_dir}")

f1, f2 = files1[0], files2[0]
print(f"Free fcst : {f1}")
print(f"DA run    : {f2}")
print()

d1 = nc.Dataset(f1)
d2 = nc.Dataset(f2)

for var, units in [("T2",   "K"),
                   ("PSFC", "Pa"),
                   ("U10",  "m/s"),
                   ("V10",  "m/s")]:
    if var not in d1.variables or var not in d2.variables:
        continue
    v1   = d1.variables[var][0]
    v2   = d2.variables[var][0]
    diff = v2 - v1
    rms  = float(np.sqrt((diff ** 2).mean()))
    print(f"{var:6s} (DA - free):  min={diff.min():+.4f}  max={diff.max():+.4f}  "
          f"mean={diff.mean():+.4f}  RMS={rms:.4f}  [{units}]")

d1.close()
d2.close()
