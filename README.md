# WRF Demo / Training Environment

A WRF training environment with installation script and hands-on exercises.

## Requirements

- **Rocky Linux 9** (or compatible RHEL 9 derivative)
- ~100-200 GB free disk space (source code, compiled libraries, WPS_GEOG data, output data files)

## What is included

### `install_demo.sh`

Compiles everything from source into a single directory (default
`~/WRF_demo_env`).  Installs:

| Component | Version |
|-----------|---------|
| WRF ARW | 4.7.1 |
| WPS | 4.6.0 |
| WRFDA | 4.7.1 |
| OpenMPI | 5.0.3 |
| HDF5 / netCDF-C / netCDF-Fortran | 1.14 / 4.9.3 / 4.6.2 |
| Python packages | numpy, matplotlib, netCDF4, cartopy |

After installation, load the environment with:

```bash
source ~/WRF_demo_env/scripts/env.sh
```

### `exercises/`

Three sequential training exercises.  Each must be completed before the next
can start — a `check_done.sh` script enforces this.

| # | Exercise | Topic |
|---|----------|-------|
| 1 | `01_basic_wrf_run` | Full WRF real-data run: WPS → real.exe → wrf.exe |
| 2 | `02_data_assimilation` | WRFDA 3D-Var data assimilation and DA-initialised forecast |
| 3 | `03_sensitivity_run` | Physics/dynamics sensitivity run and comparison against Exercise 1 |

Each exercise directory contains a `README.md` with step-by-step instructions,
ready-to-use namelists, and helper scripts for downloading input data and
plotting output.

## Quick start

```bash
# 1. Install (takes 1–2 hours on a modern machine)
bash install_demo.sh

# 2. Load the environment
source ~/WRF_demo_env/scripts/env.sh

# 3. Start Exercise 1
less ~/WRF_demo/exercises/01_basic_wrf_run/README.md
```
