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
GFS / ERA5 GRIB data
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
   - `Lambert Conformal` — best for mid-latitude domains (Europe, CONUS, …)
   - `Mercator` — better for near-equatorial domains
   - `Polar stereographic` — best for high-latitude / polar domains

4. Pan and zoom the map to your area of interest, then drag the domain box to
   position it.  Use the panel on the left to fine-tune the parameters.

5. Once satisfied, read off these values from the Domain Wizard panel and
   open the template namelist:

   ```bash
   nano $HOME/WRF_demo/exercises/01_basic_wrf_run/namelist.wps
   ```

   Edit the `&share` and `&geogrid` sections to match Domain Wizard:

   | Domain Wizard field | `namelist.wps` parameter | Example |
   |---------------------|--------------------------|---------|
   | Start date / End date | `start_date`, `end_date` | `'2019-09-04_12:00:00'` |
   | dx / dy (metres) | `dx`, `dy` | `15000` |
   | e_we (W–E grid points) | `e_we` | `150` |
   | e_sn (S–N grid points) | `e_sn` | `130` |
   | Centre latitude | `ref_lat` | `33.00` |
   | Centre longitude | `ref_lon` | `-79.00` |
   | True latitude 1 | `truelat1` | `30.0` |
   | True latitude 2 | `truelat2` | `60.0` |
   | Standard longitude | `stand_lon` | `-79.0` |
   | Projection | `map_proj` | `'lambert'` |

   Leave `geog_data_path`, `wrf_core`, `max_dom`, `interval_seconds`,
   `out_format`, `prefix`, and `fg_name` unchanged — they are already set
   correctly for this exercise.

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

### 2 — `geogrid.exe` — static geographical pre-processing

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
# Copy the namelist.wps template (already edited with your domain values in Step 0)
# and patch the geog_data_path to the demo installation
cp $HOME/WRF_demo/exercises/01_basic_wrf_run/namelist.wps $WORK/namelist.wps
sed -i "s|/home/WRF_DEMO_USER/WRF_demo_env/WPS_GEOG|${GEOG_DATA_PATH}|g" $WORK/namelist.wps

# GEOGRID.TBL tells geogrid which datasets to interpolate for each field
ln -sf $WPS_DIR/geogrid/GEOGRID.TBL.ARW $WORK/GEOGRID.TBL

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

### 3 — `ungrib.exe` — GRIB extraction

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
$WPS_DIR/link_grib.csh $HOME/WRF_demo/exercises/01_basic_wrf_run/input_grib/gfs_*.grb2
ls GRIBFILE.*

$WPS_DIR/ungrib.exe >& ungrib.log
```

**Check the log for:**
```
!!! Successful completion of ungrib.
```

```bash
tail -5 ungrib.log
ls FILE:*
```

> **Note:** Warnings about optional fields (e.g. `SEAICE`) are harmless.
> Warnings about core fields like `PRES`, `TMP`, or `HGT` mean the Vtable is wrong.

---

### 4 — `metgrid.exe` — horizontal interpolation

**What it does:**  
Reads the `geo_em` static files and the `FILE:*` intermediate files and
horizontally interpolates the meteorological data onto your WRF grid.

**Files read:**
- `namelist.wps` (`&metgrid` section)
- `geo_em.d01.nc`
- `FILE:YYYY-MM-DD_HH` (all time steps)
- `METGRID.TBL.ARW` — interpolation method per field

**Files produced:**
- `met_em.d01.YYYY-MM-DD_HH:00:00.nc`

```bash
ln -sf $WPS_DIR/metgrid/METGRID.TBL.ARW $WORK/METGRID.TBL

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
> ncdump -h met_em.d01.2019-09-04_12:00:00.nc | grep num_metgrid_levels
> ```

---

### 5 — `real.exe` — WRF initialisation

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
- `wrfinput_d01` — initial conditions at t = 0
- `wrfbdy_d01`   — lateral boundary conditions for the whole run

```bash
cp $HOME/WRF_demo/exercises/01_basic_wrf_run/namelist.input $WORK/namelist.input

# Verify num_metgrid_levels matches your met_em files and update if needed
# (replace 34 with the value you got from ncdump above)
sed -i "s/num_metgrid_levels\s*=\s*[0-9]*/num_metgrid_levels = 34/" namelist.input

# Link all WRF physics tables
for f in $WRF_DIR/run/*.TBL $WRF_DIR/run/*.asc $WRF_DIR/run/*.bin \
          $WRF_DIR/run/*.formatted $WRF_DIR/run/tr* $WRF_DIR/run/co2_trans \
          $WRF_DIR/run/MPTABLE.TBL; do
    [ -e "$f" ] && ln -sf "$f" $WORK/ || true
done

mpirun -np 1 $WRF_DIR/main/real.exe >& real.log
```

**Check the log for:**
```
d01 2019-09-04_12:00:00  real_em: SUCCESS COMPLETE REAL_EM INIT
```

```bash
grep "SUCCESS" real.log
ls -lh wrfinput_d01 wrfbdy_d01
```

> **Common pitfall:** `num_metgrid_levels` mismatch causes an immediate abort.
> Always verify against the actual `met_em` files.

---

### 6 — `wrf.exe` — the forecast model

**What it does:**  
The WRF ARW solver. Reads the IC/BC files from `real.exe` and integrates the
atmospheric equations forward in time according to the physics and dynamics
settings in `namelist.input`.

**Files read:**
- `namelist.input`
- `wrfinput_d01` (initial conditions)
- `wrfbdy_d01`   (lateral boundary conditions)
- Physics tables (same links used for `real.exe`)

**Files produced:**
- `wrfout_d01_YYYY-MM-DD_HH:00:00` — history output (one file per time step
  given `frames_per_outfile = 1`)
- `rsl.out.0000`, `rsl.error.0000` — per-rank standard output / error

```bash
# Use as many cores as you have available (MAX_CPU is set by env.sh)
mpirun -np $MAX_CPU $WRF_DIR/main/wrf.exe
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
ncdump -h wrfout_d01_2019-09-04_12:00:00

# Print 2-m temperature values at t=0
ncdump -v T2 wrfout_d01_2019-09-04_12:00:00 | tail -20
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
| `wrf.exe` crashes at t=0 | Physics table `.TBL` file missing | Check all `.TBL` files are linked in the run directory |
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
| 2 | Static geographical fields | `geogrid.exe` |
| 3 | Decode GRIB2 to WPS intermediate | `ungrib.exe` |
| 4 | Horizontal interpolation to WRF grid | `metgrid.exe` |
| 5 | Vertical interpolation, create IC/BC | `real.exe` |
| 6 | Run the NWP forecast | `wrf.exe` |
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
