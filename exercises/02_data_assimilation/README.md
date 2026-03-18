# Exercise 2 — Data Assimilation with WRFDA 3D-Var

## Prerequisites

**You must have completed Exercise 1 successfully before starting this one.**

Run the completion check now:

```bash
source $HOME/WRF_demo_env/scripts/env.sh
bash $HOME/WRF_demo/exercises/01_basic_wrf_run/check_done.sh
```

All checks must pass (especially `wrfinput_d01`, `wrfbdy_d01`, and at least
one `wrfout_d01` file from the 24-hour free forecast).  If any check fails,
go back and finish Exercise 1 first.

---

## Goal

Learn how 3D-Var data assimilation fits into the WRF modelling cycle.  You
will:

1. Download conventional observations from the NCEP NOMADS archive
2. Run the WRFDA 3D-Var minimisation with `da_wrfvar.exe` to produce an
   **analysis** — an improved initial state that blends the model first-guess
   with observations
3. Update the lateral boundary conditions with `da_update_bc.exe` so they are
   consistent with the analysis
4. Re-run `wrf.exe` starting from the analysis and compare the result with the
   free forecast from Exercise 1

> **Note on observation format:**  
> In this exercise you use NCEP GDAS PREPBUFR files (`ob.bufr`) downloaded
> directly from NOMADS.  `da_wrfvar.exe` reads them natively when
> `ob_format = 1` — no pre-processing step (`obsproc.exe`) is needed.

---

## Background — where DA fits in the WRF cycle

```
GFS GRIB  ──►  WPS  ──►  real.exe  ──►  wrfinput_d01  ──►  wrf.exe (free fcst)
                                              │
                                              │  first guess (fg)
                                              ▼
                    PREPBUFR (ob.bufr) ──► da_wrfvar.exe  (3D-Var)
                   Background error ──►    (ob_format = 1)
                    statistics (be.dat)               │
                                              ┌───────┘
                                              │  wrfvar_output (= analysis)
                                              │
                                 ┌────────────┴─────────────┐
                                 │                          │
                    cp wrfvar_output             da_update_bc.exe
                       → wrfinput_d01               (updates wrfbdy_d01
                     (new IC for WRF)            to match the analysis)
                                 │                          │
                                 └────────────┬─────────────┘
                                              ▼
                                          wrf.exe  (DA-initialised fcst)
                                              │
                                              ▼
                                      wrfout_d01_*  (analysis run)
```

**Key concept — cost function:**  
3D-Var finds the analysis **x**_a that minimises:

```
J(x) = ½ (x - xb)ᵀ B⁻¹ (x - xb)
      + ½ (yᵒ - H(x))ᵀ R⁻¹ (yᵒ - H(x))
```

where **x**_b is the background (first-guess), **B** is the background error
covariance, **y**^o are the observations, **R** is the observation error
covariance, and *H* is the observation operator.

---

## Observation data

This exercise uses conventional surface and upper-air observations from the
**NCEP GDAS PREPBUFR** archive. The
PREPBUFR format contains surface, upper-air, aircraft, and ship observations
and can be read directly by `da_wrfvar.exe` without any pre-processing step.

### Downloading observations

Use the `get_obs.sh` script provided with this exercise:

```bash
source $HOME/WRF_demo_env/scripts/env.sh

# Run interactively — the script will ask for the analysis date, cycle hour,
# and output directory, then download the PREPBUFR file from NOMADS
#Note: Use same dates than in exercise 1
bash $HOME/WRF_demo/exercises/02_data_assimilation/get_obs.sh
```

When prompted:
- **Analysis date:** `YYYMMDD`
- **Analysis hour:** `HH`
- **Output directory:** `$HOME/WRF_demo_env/run/ex02` (or press Enter to accept the default)

The script downloads `gdas.t12z.prepbufr.nr` from the NOMADS GDAS archive
and saves it as `ob.bufr` in the output directory.

---

## Directory layout

```
02_data_assimilation/
├── README.md                 ← this file
├── get_obs.sh                ← interactive NCEP observation download script
├── namelist.input.wrfda      ← WRFDA 3D-Var namelist (ob_format = 1)
├── parame.in                 ← da_update_bc configuration
├── check_increments.py       ← print analysis increment statistics
├── compare_runs.py           ← compare free forecast vs DA-initialised forecast
└── check_done.sh             ← run when finished
```

Working directory for this exercise: `$BASE_DIR/run/ex02/`

---

## Step-by-step walkthrough

### 0 — Set up the working directory

```bash
source $HOME/WRF_demo_env/scripts/env.sh

EX1=$BASE_DIR/run/ex01
WORK=$BASE_DIR/run/ex02
mkdir -p $WORK
cd $WORK
```

Copy the IC/BC files produced by Exercise 1 — these are the **first guess**
for the DA system:

```bash
cp $EX1/wrfinput_d01  $WORK/
cp $EX1/wrfbdy_d01    $WORK/
cp $EX1/wrflowinp_d01 $WORK/
```

---

### 1 — Prepare the observation file

**What we use:**  
NCEP GDAS PREPBUFR (`ob.bufr`) downloaded in the *Observation data* section
above.  `da_wrfvar.exe` reads PREPBUFR directly when `ob_format = 1` is set
in the namelist — no `obsproc.exe` pre-processing step is required.

Verify the file is present and non-empty:

```bash
ls -lh $WORK/ob.bufr
```

> **What is PREPBUFR?**  
> PREPBUFR is NCEP's binary BUFR format for conventional (non-satellite)
> observations: surface synoptic stations (SYNOP/METAR), radiosondes (SOUND),
> aircraft (AIREP), ships, and wind profilers.  The GDAS PREPBUFR file
> applies first-guess quality control marks before the DA cycle, which helps
> reject gross observation errors automatically.

---

### 2 — `da_wrfvar.exe` — 3D-Var minimisation

**What it does:**  
This is the core WRFDA executable.  It reads the first-guess `wrfinput_d01`
(or a `fg` file from a previous WRF run in a cycling system), the observations
processed by `obsproc.exe`, and the background error statistics (`be.dat`).
It then minimises the cost function $J$ iteratively (inner-loop CG iterations)
to produce the **analysis** — a physically consistent atmospheric state that
is closer to the observations than the first guess.

**Files read:**
- `namelist.input` (the WRFDA namelist, which you copy from `namelist.input.wrfda`)
- `fg` — first-guess file (a symlink to `wrfinput_d01` for a cold start)
- `ob.bufr` — PREPBUFR observations (used directly when `ob_format = 1`)
- `be.dat` — background error covariance statistics
- `LANDUSE.TBL`, `VEGPARM.TBL`, etc. — same physics tables as WRF

**Files produced:**
- `wrfvar_output` — the **analysis file** (same format as `wrfinput_d01`)
- `namelist.output` — the final namelist as actually read
- `cost_fn` and `grad_fn` — cost function convergence history
- `statistics` — observation-minus-background and observation-minus-analysis stats
- `gts_omb_oma_01` — O-B and O-A diagnostics per observation

```bash
cd $WORK

# WRFDA reads its namelist from a file literally named 'namelist.input'
cp $HOME/WRF_demo/exercises/02_data_assimilation/namelist.input.wrfda $WORK/namelist.input

# Edit the namelist to match your analysis date
```

Update all date/time parameters to match your `start_date` from `namelist.wps`:

| Parameter | Description | Example (`start_date = 2026-03-17_12:00:00`) |
|-----------|-------------|----------------------------------------------|
| `analysis_date` | Exact analysis time | `'2026-03-17_12:00:00.0000'` |
| `time_window_min` | Earliest obs accepted (−1 h) | `'2026-03-17_11:00:00.0000'` |
| `time_window_max` | Latest obs accepted (+1 h) | `'2026-03-17_13:00:00.0000'` |
| `start_year/month/day/hour` | Same as `analysis_date` | `2026, 03, 17, 12` |
| `end_year/month/day/hour` | Same as `analysis_date` | `2026, 03, 17, 12` |

Also update the domain parameters to match your `namelist.wps` / `namelist.input`:

| Parameter | Where to get the value |
|-----------|------------------------|
| `e_we` | Same as in `namelist.wps` |
| `e_sn` | Same as in `namelist.wps` |
| `e_vert` | Same as in `namelist.input` (from Exercise 1) |
| `dx` | Same as in `namelist.wps` |
| `dy` | Same as in `namelist.wps` |

```bash
ln -sf $WORK/wrfinput_d01 $WORK/fg

# Observations: ob.bufr is the PREPBUFR file (ob_format = 1 in namelist.input)
# It should already be in $WORK from Step 1 — confirm it is there:
ls -lh $WORK/ob.bufr

# Background error statistics — CV3 is a global NMC-derived be.dat
# provided with the WRFDA installation
ln -sf $WRFDA_DIR/var/run/be.dat.cv3 $WORK/be.dat

# Link required physics and run tables
ln -sf $WRFDA_DIR/run/LANDUSE.TBL          $WORK/
ln -sf $WRFDA_DIR/var/run/leapsec.dat      $WORK/
ln -sf $WRFDA_DIR/var/run/VARBC.in         $WORK/
ln -sf $WRFDA_DIR/var/run/radiance_info    $WORK/

mpirun -np 4 $WRFDA_DIR/var/da/da_wrfvar.exe >& wrfda.log
```

**Check the log for:**
```
 wrfvar completed successfully
```

```bash
grep -E "wrfvar completed|Cost function|iter" wrfda.log | tail -15
ls -lh wrfvar_output
```

> **Reading cost function convergence:**
> ```bash
> cat cost_fn
> ```
> Each line shows the cost $J$ at each outer/inner iteration.  The value
> should decrease monotonically.  If it stagnates after iteration 1, there
> may be no valid observations inside the domain.

> **Inspecting O-B / O-A statistics:**
> ```bash
> cat statistics
> ```
> This shows, for each observation type, the mean and RMS of
> observation-minus-background (O-B) and observation-minus-analysis (O-A).
> The O-A values should be smaller than O-B — this confirms the analysis
> moved towards the observations.

---

### 3 — `da_update_bc.exe` — update boundary conditions

**What it does:**  
After 3D-Var, two things must happen before `wrf.exe` can start from the analysis:

1. **`wrfinput_d01` must be replaced by `wrfvar_output`** — so WRF starts from
   the analysis state rather than the original GFS first-guess.
2. **`wrfbdy_d01` must be updated** — the lateral boundary tendencies at t=0
   still correspond to the first-guess state; `da_update_bc.exe` adjusts them
   to be consistent with the new analysis, preventing a boundary discontinuity.

**Files read:**
- `parame.in` — control parameters
- `wrfvar_output` (the analysis, referenced as `da_file`)
- `wrfinput_d01` (read for land-surface/lower-boundary fields)
- `wrfbdy_d01` (updated in-place)

**Files produced:**
- `wrfbdy_d01` updated in-place (first BDY time level adjusted to match analysis)
- `wrfinput_d01` replaced by `wrfvar_output` (the analysis becomes the new IC)

```bash
cd $WORK

cp $HOME/WRF_demo/exercises/02_data_assimilation/parame.in $WORK/parame.in

ln -sf $WRFDA_DIR/var/da/da_update_bc.exe $WORK/

# Step 1: replace wrfinput_d01 with the analysis
cp $WORK/wrfvar_output $WORK/wrfinput_d01

# Step 2: update wrfbdy_d01 to be consistent with the analysis
mpirun -np 1 $WORK/da_update_bc.exe >& update_bc.log
```

**Check the log for:**
```
 da_update_bc: updated wrfinput  successfully
 da_update_bc: updated wrfbdy    successfully
```

```bash
tail -10 update_bc.log
```

> **Verifying the analysis increments:**  
> You can inspect the difference between the analysis and the original
> first-guess **before** copying `wrfvar_output` over `wrfinput_d01`:
> ```bash
> python3 $HOME/WRF_demo/exercises/02_data_assimilation/check_increments.py \
>     $EX1/wrfinput_d01 $WORK/wrfvar_output
> ```
> Non-zero values confirm the 3D-Var minimisation applied increments.  
> If all values are zero, no observations were assimilated — check `statistics`.

---

### 4 — `wrf.exe` — the DA-initialised forecast

Now run WRF again, but this time starting from the analysis.  The
`wrfinput_d01` file in `$WORK` has been updated by `da_update_bc.exe` and
represents the improved initial state.

```bash
cd $WORK

# Link all files from the WRF run directory (tables, data files, executables)
# Exclude namelist.input — that is managed manually in $WORK
for f in $WRF_DIR/run/*; do
    [[ -f "$f" && "$(basename $f)" != "namelist.input" ]] && ln -sf "$f" $WORK/ || true
done

# Use the WRF namelist from Exercise 1 (already edited with your domain/dates)
cp $EX1/namelist.input $WORK/namelist.input

# Clean up any previous rsl files
rm -f rsl.out.* rsl.error.*

mpirun -np 4 $WRF_DIR/main/wrf.exe
```

> **Monitor progress:**
> ```bash
> tail -f $WORK/rsl.out.0000
> ```

**Check for successful completion:**
```bash
grep "SUCCESS COMPLETE WRF" rsl.out.0000
ls -lh wrfout_d01_*
```

---

## Comparing free forecast vs DA-initialised forecast

You now have two sets of output:

| Run | Directory | Initial state |
|-----|-----------|---------------|
| Free forecast (Ex 1) | `$BASE_DIR/run/ex01/` | GFS interpolation only |
| DA-initialised (Ex 2) | `$BASE_DIR/run/ex02/` | GFS + observed increments |

Compare 2-m temperature and surface pressure between the two runs at the first output time:

```bash
python3 $HOME/WRF_demo/exercises/02_data_assimilation/compare_runs.py \
    $BASE_DIR/run/ex01 $BASE_DIR/run/ex02
```

Non-zero differences confirm the DA analysis affected the forecast.  Larger
RMS values indicate stronger observation impact in those regions.

---

## What can go wrong — quick troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `da_wrfvar.exe` aborts with `Cannot find ob.bufr` | PREPBUFR file missing | Run `get_obs.sh` and ensure `ob.bufr` is in `$WORK` |
| `da_wrfvar.exe` aborts with `Cannot find fg` | `fg` symlink missing or broken | `ln -sf $WORK/wrfinput_d01 $WORK/fg` |
| `da_wrfvar.exe` aborts with `be.dat` error | Missing or wrong background error file | Check `ln -sf ... be.dat` is correct |
| Cost function does not decrease | No valid obs inside domain | Check `statistics` file; verify `ob.bufr` contains obs inside the WRF grid |
| `statistics` shows 0 obs used | Date mismatch between PREPBUFR and `analysis_date` | Confirm `ob.bufr` cycle matches `analysis_date`, `time_window_min/max`, and `start/end` dates in `namelist.input` |
| `da_update_bc.exe` aborts | `parame.in` paths wrong | Ensure `da_file`, `wrf_input`, `wrf_bdy_file` point to files in `$WORK` |
| `wrf.exe` crashes at t=0 after DA | `wrfinput_d01` / `wrfbdy_d01` inconsistency | Re-run `da_update_bc.exe`; check the log for errors |
| `wrf.exe` fatal: `missing file for = auxinput4` | `wrflowinp_d01` not copied from Exercise 1 | `cp $EX1/wrflowinp_d01 $WORK/` |

---

## Key files reference

| File | Purpose |
|------|---------|
| `ob.bufr` | NCEP GDAS PREPBUFR observations (input to `da_wrfvar.exe`, `ob_format = 1`) |
| `fg` | First-guess (symlink to `wrfinput_d01`) |
| `be.dat` | Background error covariance statistics |
| `wrfvar_output` | Analysis file (output of `da_wrfvar.exe`) |
| `cost_fn` | Cost function convergence history |
| `statistics` | O-B / O-A diagnostic summary |
| `gts_omb_oma_01` | Per-observation O-B / O-A diagnostics |
| `parame.in` | Control file for `da_update_bc.exe` |

---

## Completion check

When you have a successful `wrfout_d01` from the DA-initialised run, run:

```bash
bash $HOME/WRF_demo/exercises/02_data_assimilation/check_done.sh
```

---

*Previous exercise →* **[Exercise 1 — A Basic Real-Data WRF Run](../01_basic_wrf_run/README.md)**
