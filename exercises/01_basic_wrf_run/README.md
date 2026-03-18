# Exercise 1 — A Basic Real-Data WRF Run

## Goal

Walk through a complete WRF pre-processing → initialisation → forecast cycle,
running every executable by hand so you understand what each one does, what it
reads, and what it produces.


---

## Directory layout

```
01_basic_wrf_run/
├── README.md              ← this file
├── get_gfs.sh             ← download GFS boundary data from NOMADS
├── namelist.wps           ← WPS configuration — edit domain values from Domain Wizard here
├── namelist.input         ← WRF configuration (24-h, CONUS physics suite)
├── plot_wrf_output.py     ← visualise key output fields (T2, wind, PSFC, Q2)
├── check_done.sh          ← run this when finished to verify your outputs
└── input_grib/            ← GFS GRIB2 files land here after get_gfs.sh
```

A `run/ex01/` working directory will be created inside `$BASE_DIR` when you
start running the executables.

---

## Background — the WRF workflow

```
GFS GRIB data
        │
        ▼
  ┌─────────────┐
  │  geogrid    │  Creates static geographical fields (terrain, land-use, …)
  └──────┬──────┘        → geo_em.d01.nc
         │
  ┌──────▼──────┐
  │   ungrib    │  Decodes GRIB files into WPS intermediate format
  └──────┬──────┘        → FILE:YYYY-MM-DD_HH (one per time step)
         │
  ┌──────▼──────┐
  │   metgrid   │  Horizontally interpolates met fields onto the WRF grid
  └──────┬──────┘        → met_em.d01.YYYY-MM-DD_HH:00:00.nc
         │
  ┌──────▼──────┐
  │   real.exe  │  Vertically interpolates, creates IC/BC files
  └──────┬──────┘        → wrfinput_d01, wrfbdy_d01
         │
  ┌──────▼──────┐
  │   wrf.exe   │  The actual NWP forecast model
  └─────────────┘        → wrfout_d01_YYYY-MM-DD_HH:00:00
```

---

## Step-by-step walkthrough

### 0 — Define your domain with WRF Domain Wizard

Before running any executable you need to decide **where** your model domain
will be: its projection, centre point, grid spacing, and size in grid points.
Use [WRF Domain Wizard](https://jiririchter.github.io/WRFDomainWizard/) to
design the domain interactively on a map, then copy the key values it gives
you into the provided `namelist.wps` template.

**Steps:**

1. Open **<https://jiririchter.github.io/WRFDomainWizard/>** in a web browser.

2. Click **Add domain** (the `+` button in the top-left panel).

3. Choose a **map projection**:
   - `Lambert Conformal` — best for mid-latitude domains (Europe, …)
   - `Mercator` — better for near-equatorial domains
   - `Polar stereographic` — best for high-latitude / polar domains

4. Pan and zoom the map to your area of interest, then drag the domain box to
   position it.  Use the panel on the left to fine-tune the parameters.

5. Once satisfied, make a note of the parameter values shown in the Domain Wizard
   panel — you will enter them into `namelist.wps` later.

6. Make a note of your domain's approximate bounding box (westernmost,
   easternmost, southernmost, northernmost corners in degrees) — you will need
   these values when `get_gfs.sh` asks for the download region.

> **Tips for choosing a good domain:**
> - Add at least 10 grid points of buffer on each side beyond your area of
>   interest — the lateral boundary zone needs room to relax.
> - Keep the domain aspect ratio close to square for best performance.
> - For a first test run, a small domain (~100×100 grid points at 15 km)
>   will complete in minutes on a modest machine.

---

### 1 — Prepare the working directory

```bash
source $HOME/WRF_demo_env/scripts/env.sh

WORK=$BASE_DIR/run/ex01
mkdir -p $WORK
cd $WORK
```

All commands below assume your shell is in `$WORK`.

---

### 2 — Download GFS boundary data

**What it does:**  
Fetches GFS 0.25° GRIB2 files from the NOAA NOMADS filter server for the
model cycle that matches your `start_date` / `end_date`.  Only the pressure
levels, surface fields, and variables that WPS actually needs are requested,
so each file stays a manageable size.

The script asks four questions interactively:

| Prompt | Where to get the value |
|--------|------------------------|
| Cycle date (`YYYYMMDD`) | Your `start_date` in `namelist.wps` (date part) |
| Cycle hour (`00/06/12/18`) | Your `start_date` in `namelist.wps` (hour part, only 00,06,12 and 18 UTC available) |
| Forecast length (hours) | `end_date` − `start_date` (e.g. 24 for a 24-h run) |
| Interval between files (hours) | `interval_seconds` ÷ 3600 (typically `3` or `6`) |
| Domain bounding box (N/S/W/E) | From Step 0 — add ~10° margin on every side |

**Files produced** (in `input_grib/` inside the exercise directory):
- `gfs_YYYY-MM-DD_HH.grb2` — one file per requested time step

```bash
# Run from $WORK — the script always writes into the exercise's input_grib/
bash $HOME/WRF_demo/exercises/01_basic_wrf_run/get_gfs.sh
```

After the script finishes, verify the files are present and non-zero:

```bash
ls -lh $WORK/input_grib/gfs_*.grb2
```

You should see one `.grb2` file per time step (e.g. 9 files for a 24-h run at
3-h intervals: f000, f003, f006, … f024).

> **Tip:** Run `bash $HOME/WRF_demo/exercises/01_basic_wrf_run/get_gfs.sh -n` first for a **dry run** — it prints the
> URLs and settings without downloading anything, so you can sanity-check your
> inputs before committing to the transfer.

> **Note:** NOMADS only keeps the most recent ~5 days of GFS output.  
---

### 4 — `geogrid.exe` — static geographical pre-processing

**What it does:**  
Reads `namelist.wps` (`&geogrid` section) and interpolates high-resolution
static datasets (terrain height, land-use category, soil type, vegetation
fraction, …) from the `WPS_GEOG` tile library onto your model grid.  
Produces one NetCDF file per domain: `geo_em.dNN.nc`.

**Files read:**
- `namelist.wps`
- `$GEOG_DATA_PATH/**` — the WPS_GEOG static tile library

**Files produced:**
- `geo_em.d01.nc`

```bash
# Copy the namelist.wps template to $WORK and edit it there
cp $HOME/WRF_demo/exercises/01_basic_wrf_run/namelist.wps $WORK/namelist.wps

# Patch geog_data_path to the demo installation path
sed -i "s|/home/WRF_DEMO_USER/WRF_demo_env/WPS_GEOG|${GEOG_DATA_PATH}|g" $WORK/namelist.wps

# Now edit the domain parameters you noted in Step 0
```

Edit the `&share` and `&geogrid` sections to match Domain Wizard:

| Domain Wizard field | `namelist.wps` parameter | Example |
|---------------------|--------------------------|---------|
| Start date / End date | `start_date`, `end_date` | `2026-03-17_12:00:00` |
| dx / dy (metres) | `dx`, `dy` | `15000` |
| e_we (W–E grid points) | `e_we` | `150` |
| e_sn (S–N grid points) | `e_sn` | `130` |
| Centre latitude | `ref_lat` | `33.00` |
| Centre longitude | `ref_lon` | `-79.00` |
| True latitude 1 | `truelat1` | `30.0` |
| True latitude 2 | `truelat2` | `60.0` |
| Standard longitude | `stand_lon` | `-79.0` |
| Projection | `map_proj` | `'lambert'` |

Leave `geog_data_path`, `wrf_core`, `max_dom`, `interval_seconds`, `out_format`,
`prefix`, and `fg_name` unchanged.

```bash
# namelist.wps sets opt_geogrid_tbl_path = 'geogrid/', so the table must live there
mkdir -p $WORK/geogrid
ln -sf $WPS_DIR/geogrid/GEOGRID.TBL.ARW $WORK/geogrid/GEOGRID.TBL

$WPS_DIR/geogrid.exe >& geogrid.log
```

**Check the log for:**
```
!!! Successful completion of geogrid.
```

```bash
tail -5 geogrid.log
ls -lh geo_em.d01.nc
```

> **Tip:** Inspect the domain with `ncdump -h geo_em.d01.nc | grep -E "XLAT_M|DX|DY"`.

---

### 5 — `ungrib.exe` — GRIB extraction

**What it does:**  
Reads the raw GRIB2 files from GFS and writes them into the WPS intermediate
binary format.  One intermediate file is produced per time step.

**Files read:**
- `namelist.wps` (`&ungrib` section)
- `Vtable` — field-name mapping table for the data source
- GRIB2 files linked as `GRIBFILE.AAA`, `GRIBFILE.AAB`, …

**Files produced:**
- `FILE:YYYY-MM-DD_HH` (one per time step)

```bash
# Link the Vtable for GFS GRIB2 data
ln -sf $WPS_DIR/ungrib/Variable_Tables/Vtable.GFS $WORK/Vtable

# Remove any old links/files from previous attempts
rm -f $WORK/GRIBFILE.* $WORK/FILE:*

# link_grib.csh creates GRIBFILE.AAA, .AAB, … links from your GRIB files
$WPS_DIR/link_grib.csh $WORK/input_grib/gfs_*.grb2
ls GRIBFILE.*

$WPS_DIR/ungrib.exe >& ungrib.log
```

**Check the log for:**
```
!!! Successful completion of ungrib.
```

```bash
tail -5 ungrib.log
ls GFS:*
```

> **Note:** Warnings about optional fields (e.g. `SEAICE`) are harmless.
> Warnings about core fields like `PRES`, `TMP`, or `HGT` mean the Vtable is wrong.

---

### 6 — `metgrid.exe` — horizontal interpolation

**What it does:**  
Reads the `geo_em` static files and the `GFS:*` intermediate files and
horizontally interpolates the meteorological data onto your WRF grid.

**Files read:**
- `namelist.wps` (`&metgrid` section)
- `geo_em.d01.nc`
- `GFS:YYYY-MM-DD_HH` (all time steps)
- `METGRID.TBL.ARW` — interpolation method per field

**Files produced:**
- `met_em.d01.YYYY-MM-DD_HH:00:00.nc`

```bash
# namelist.wps sets opt_metgrid_tbl_path = 'metgrid/', so the table must live there
mkdir -p $WORK/metgrid
ln -sf $WPS_DIR/metgrid/METGRID.TBL.ARW $WORK/metgrid/METGRID.TBL

$WPS_DIR/metgrid.exe >& metgrid.log
```

**Check the log for:**
```
!!! Successful completion of metgrid.
```

```bash
tail -5 metgrid.log
ls met_em.d01.*.nc
```

> **Important:** Note how many pressure levels the met_em files contain —
> you will need this value for `namelist.input`:
> ```bash
> ncdump -h met_em.d01.YYYY-MM-DD_HH:00:00.nc | grep num_metgrid_levels
> ```

---

### 7 — `real.exe` — WRF initialisation

**What it does:**  
Reads the `met_em` files and `namelist.input` and:
- vertically interpolates GFS pressure-level data onto WRF's hybrid-sigma levels,
- creates the initial conditions file (`wrfinput_d01`),
- creates the lateral boundary conditions file (`wrfbdy_d01`).

`real.exe` is the bridge between WPS (geographical space) and the WRF model
(grid-index / sigma-level space).

**Files read:**
- `namelist.input`
- `met_em.d01.*.nc`
- Physics look-up tables (`*.TBL`, `MPTABLE.TBL`, etc.)

**Files produced:**
- `wrfinput_d01`   — initial conditions at t = 0
- `wrfbdy_d01`     — lateral boundary conditions for the whole run
- `wrflowinp_d01`  — time-varying lower boundary conditions (SST, sea-ice) used by `wrf.exe` when `sst_update = 1`

Copy the template to `$WORK` first, then edit it there:

```bash
cp $HOME/WRF_demo/exercises/01_basic_wrf_run/namelist.input $WORK/namelist.input

```

Update these parameters to match your `namelist.wps` and your actual `met_em` files:

| Parameter | Where to get the value |
|-----------|------------------------|
| `start_year/month/day/hour` | Your `start_date` in `namelist.wps` |
| `end_year/month/day/hour` | Your `end_date` in `namelist.wps` |
| `run_days` / `run_hours` | Length of the forecast (e.g. `run_days = 1, run_hours = 0` for 24 h) |
| `interval_seconds` | Same as in `namelist.wps` (e.g. `10800` for 3-h GFS output) |
| `e_we` / `e_sn` | Same grid dimensions as in `namelist.wps` |
| `dx` / `dy` | Same grid spacing as in `namelist.wps` |
| `num_metgrid_levels` | From `ncdump -h met_em.d01.*.nc \| grep num_metgrid_levels` |

```bash

# Link all files from the WRF run directory (tables, data files, executables)
# Exclude namelist.input — that is managed manually in $WORK
for f in $WRF_DIR/run/*; do
    [[ -f "$f" && "$(basename $f)" != "namelist.input" ]] && ln -sf "$f" $WORK/ || true
done

mpirun -np 1 $WRF_DIR/main/real.exe >& real.log
```

**Check the log for:**
```
d01 2019-09-04_12:00:00  real_em: SUCCESS COMPLETE REAL_EM INIT
```

```bash
grep "SUCCESS" real.log
ls -lh wrfinput_d01 wrfbdy_d01 wrflowinp_d01
```

> **Common pitfall:** `num_metgrid_levels` mismatch causes an immediate abort.
> Always verify against the actual `met_em` files.

---

### 8 — `wrf.exe` — the forecast model

**What it does:**  
The WRF ARW solver. Reads the IC/BC files from `real.exe` and integrates the
atmospheric equations forward in time according to the physics and dynamics
settings in `namelist.input`.

**Files read:**
- `namelist.input`
- `wrfinput_d01`  (initial conditions)
- `wrfbdy_d01`    (lateral boundary conditions)
- `wrflowinp_d01` (time-varying SST/sea-ice, required when `sst_update = 1`)
- Physics tables (same links used for `real.exe`)

**Files produced:**
- `wrfout_d01_YYYY-MM-DD_HH:00:00` — history output (one file per time step
  given `frames_per_outfile = 1`)
- `rsl.out.0000`, `rsl.error.0000` — per-rank standard output / error

```bash
# Use as many cores as you have available 
mpirun -np 4 $WRF_DIR/main/wrf.exe
```

> **Monitor progress** in a second terminal:
> ```bash
> tail -f $BASE_DIR/run/ex01/rsl.out.0000
> ```
> WRF prints a timing line for each simulated time step.  A stalled run with
> no new lines usually means a crash — check `rsl.error.0000`.

**Check for successful completion:**
```bash
grep "SUCCESS COMPLETE WRF" rsl.out.0000
ls -lh wrfout_d01_*
```

---

## Inspecting the output

```bash
# List all variables in the first output file
ncdump -h wrfout_d01_YYYY-MM-DD_HH:00:00

# Print 2-m temperature values at t=0
ncdump -v T2 wrfout_d01_YYYY-MM-DD_HH:00:00 | tail -20
```

### Visualisation

A Python visualisation script is provided that plots four key parameters from
any wrfout file into a single PNG:

| Panel | Variable | Units |
|-------|----------|-------|
| Left   | 2-m Temperature | °C |
| Centre | 10-m Wind speed + vectors | m/s |
| Right  | Surface Pressure | hPa |

Run it from your WRF working directory (where the `wrfout` files are):

```bash
cd $BASE_DIR/run/ex01

# Plot the first time step of the first wrfout file found:
python3 $HOME/WRF_demo/exercises/01_basic_wrf_run/plot_wrf_output.py

# Or specify a file and time index explicitly:
python3 $HOME/WRF_demo/exercises/01_basic_wrf_run/plot_wrf_output.py \
    wrfout_d01_2019-09-04_12:00:00 --time 0
```

The script saves `wrf_output_<date>_<hour>UTC.png` in the current directory.
Use `--out myfile.png` to choose a different output filename.

> **Requirements:** `numpy`, `matplotlib`, `netCDF4`, and `cartopy` —
> all installed automatically by `install_demo.sh`.

---

## What can go wrong — quick troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `geogrid.exe` aborts with `geog_data_path` error | Wrong path in `namelist.wps` | Confirm `echo $GEOG_DATA_PATH` and update the namelist |
| `ungrib.exe` produces no `FILE:*` | Vtable mismatch or missing GRIBFILE links | Check `ls GRIBFILE.*`; verify Vtable matches data source |
| `metgrid.exe` `0 fields` warning | `fg_name` in namelist doesn't match ungrib prefix | Set `fg_name = 'FILE'` |
| `real.exe` aborts immediately | `num_metgrid_levels` mismatch | Query from met_em: `ncdump -h met_em.*.nc \| grep num_metgrid_levels` |
| `wrf.exe` fatal: `missing file for = auxinput4` | `wrflowinp_d01` not in run directory | `ln -sf $BASE_DIR/run/ex01/wrflowinp_d01 $WORK/` |
| `wrf.exe` crashes at t=0 | Physics table or data file missing | Re-run the full link loop: `for f in $WRF_DIR/run/*; do [[ -f "$f" && "$(basename $f)" != "namelist.input" ]] && ln -sf "$f" $WORK/; done` |
| `wrf.exe` fatal: `CAMtr_volume_mixing_ratio does not exist` | Extension-less data file not linked | Included in the loop above — re-run it |
| `wrf.exe` fatal: `RRTMG_LW_DATA`/`RRTMG_SW_DATA` not found | Extension-less RRTMG data file not linked | Included in the loop above — re-run it |
| `wrf.exe` CFL violation | Time step too large | Reduce `time_step` (rule of thumb: `dx_km × 6`) |

---

## Completion check

When your `wrfout` files look good, run the completion check to verify all
required outputs are present before moving on to Exercise 2:

```bash
bash $HOME/WRF_demo/exercises/01_basic_wrf_run/check_done.sh
```

All checks must pass before you start Exercise 2.

---

## Summary of steps

| Step | Action | Tool / Executable |
|------|--------|-------------------|
| 0 | Design domain interactively | [WRF Domain Wizard](https://jiririchter.github.io/WRFDomainWizard/) |
| 1 | Prepare working directory | `bash` |
| 2 | Download GFS boundary data | `get_gfs.sh` |
| 3 | Static geographical fields | `geogrid.exe` |
| 4 | Decode GRIB2 to WPS intermediate | `ungrib.exe` |
| 5 | Horizontal interpolation to WRF grid | `metgrid.exe` |
| 6 | Vertical interpolation, create IC/BC | `real.exe` |
| 7 | Run the NWP forecast | `wrf.exe` |
| — | Visualise output | `plot_wrf_output.py` |

| Executable | Component | Input | Output |
|---|---|---|---|
| `geogrid.exe` | WPS | `namelist.wps` + WPS_GEOG tiles | `geo_em.d01.nc` |
| `ungrib.exe` | WPS | `namelist.wps` + GRIB files + Vtable | `FILE:YYYY-MM-DD_HH` |
| `metgrid.exe` | WPS | `namelist.wps` + geo_em + FILE:* | `met_em.d01.YYYY-MM-DD_HH:00:00.nc` |
| `real.exe` | WRF | `namelist.input` + met_em + tables | `wrfinput_d01`, `wrfbdy_d01` |
| `wrf.exe` | WRF | `namelist.input` + wrfinput + wrfbdy + tables | `wrfout_d01_*` |

---

*Next exercise →* **[Exercise 2 — Data Assimilation with WRFDA 3D-Var](../02_data_assimilation/README.md)**  
*(Complete the check above first!)*
