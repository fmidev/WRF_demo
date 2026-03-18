#!/usr/bin/env python3
"""
check_increments.py  —  Print analysis increment statistics for wrfinput files.

Usage:
    python3 check_increments.py <first_guess> <analysis>

Example:
    python3 check_increments.py $EX1/wrfinput_d01 wrfinput_d01
"""

import sys
import numpy as np
import netCDF4 as nc

if len(sys.argv) != 3:
    sys.exit("Usage: check_increments.py <first_guess> <analysis>")

fg_path, ana_path = sys.argv[1], sys.argv[2]

fg  = nc.Dataset(fg_path)
ana = nc.Dataset(ana_path)

print(f"First-guess : {fg_path}")
print(f"Analysis    : {ana_path}")
print()

for var, units in [("T",      "K (perturbation potential temp)"),
                   ("U",      "m/s"),
                   ("V",      "m/s"),
                   ("QVAPOR", "kg/kg"),
                   ("PH",     "m2/s2 (geopotential perturbation)")]:
    if var not in fg.variables or var not in ana.variables:
        continue
    inc = ana.variables[var][0] - fg.variables[var][0]
    rms = float(np.sqrt((inc ** 2).mean()))
    print(f"{var:8s}  min={inc.min():+.4f}  max={inc.max():+.4f}  "
          f"mean={inc.mean():+.4f}  RMS={rms:.4f}  [{units}]")

print()
print("Note: 2D diagnostic fields (T2, U10, V10) are not directly updated by")
print("3D-Var — only 3D model-state variables (T, U, V, QVAPOR, PH) are analysed.")

fg.close()
ana.close()
