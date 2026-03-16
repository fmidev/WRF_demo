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
                                              ▼
                                     da_update_bc.exe
                                              │  updated wrfinput_d01
                                              │  updated wrfbdy_d01
                                              ▼
                                          wrf.exe  (DA-initialised fcst)
                                              │
                                              ▼
                                      wrfout_d01_*  (analysis run)
```

**Key concept — cost function:**  
3D-Var finds the analysis $\mathbf{x}_a$ that minimises:

$$J(\mathbf{x}) = \frac{1}{2}(\mathbf{x}-\mathbf{x}_b)^T \mathbf{B}^{-1}
(\mathbf{x}-\mathbf{x}_b)
+ \frac{1}{2}(\mathbf{y}^o - H(\mathbf{x}))^T \mathbf{R}^{-1}
(\mathbf{y}^o - H(\mathbf{x}))$$

where $\mathbf{x}_b$ is the background (first-guess), $\mathbf{B}$ is the
background error covariance, $\mathbf{y}^o$ are the observations,
$\mathbf{R}$ is the observation error covariance, and $H$ is the observation
operator.

---

## Observation data

This exercise uses conventional surface and upper-air observations from the
**NCEP GDAS PREPBUFR** archive, valid at **2019-09-04 12 UTC**.  The
PREPBUFR format contains surface, upper-air, aircraft, and ship observations
and can be read directly by `da_wrfvar.exe` without any pre-processing step.

### Downloading observations

Use the `get_obs.sh` script provided with this exercise:

```bash
source $HOME/WRF_demo_env/scripts/env.sh

# Run interactively — the script will ask for the analysis date, cycle hour,
# and output directory, then download the PREPBUFR file from NOMADS
bash $HOME/WRF_demo/exercises/02_data_assimilation/get_obs.sh
```

When prompted:
- **Analysis date:** `20190904`
- **Analysis hour:** `12`
- **Output directory:** `$HOME/WRF_demo_env/run/ex02` (or press Enter to accept the default)

The script downloads `gdas.t12z.prepbufr.nr` from the NOMADS GDAS archive
and saves it as `ob.bufr` in the output directory.

> **Archive availability:**  
> NOMADS keeps recent GDAS files for approximately 10 days.  The 2019-09-04
> case used in this exercise is older than that, so the file will not be on
> the real-time NOMADS server.  In that case you can:
> - Request the file from the **NCAR RDA dataset ds337.0**:
>   <https://rda.ucar.edu/datasets/ds337.0/>
>   (requires a free UCAR account)
> - Download GDAS PREPBUFR from the **NCEI archive** (tape-backed):
>   <https://www.ncei.noaa.gov/access/global-radiosonde-archive/>
> - Use the **WRFDA tutorial dataset** (different date — 2008-02-05 12 UTC)
>   and update all dates in the namelists accordingly:
>   ```bash
>   wget https://www2.mmm.ucar.edu/wrf/src/WRFDA_tutorial_data/2008020512.tar.gz
>   tar -xf 2008020512.tar.gz
>   # The archive contains ob.bufr (prepbufr) ready for ob_format=1
>   ```

---

## Directory layout

```
02_data_assimilation/
├── README.md                 ← this file
├── get_obs.sh                ← interactive NCEP observation download script
├── namelist.input.wrfda      ← WRFDA 3D-Var namelist (ob_format = 1)
├── parame.in                 ← da_update_bc configuration
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
cp $EX1/wrfinput_d01 $WORK/
cp $EX1/wrfbdy_d01   $WORK/
```

---

### 1 — Prepare the observation file

**What we use:**  
NCEP GDAS PREPBUFR (`ob.bufr`) downloaded in the *Observation data* section
above.  `da_wrfvar.exe` reads PREPBUFR directly when `ob_format = 1` is set
in the namelist — no `obsproc.exe` pre-processing step is required.

Move or link the downloaded file into the working directory:

```bash
cd $WORK

# If get_obs.sh already saved ob.bufr to $WORK, you can skip this line.
# Otherwise link or copy it from wherever you downloaded it:
ln -sf $HOME/WRF_demo_env/run/ex02/ob.bufr $WORK/ob.bufr
```

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

# First guess: use the real.exe output as a cold-start first guess
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

mpirun -np $MAX_CPU $WRFDA_DIR/var/da/da_wrfvar.exe >& wrfda.log
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
After 3D-Var, the analysis (`wrfvar_output`) is physically consistent inside
the domain but the lateral boundary conditions in `wrfbdy_d01` still correspond
to the original first-guess state.  `da_update_bc.exe` updates the first time
level of the boundary tendencies in `wrfbdy_d01` to be consistent with the
new analysis, preventing a discontinuity at the domain boundary when the
DA-initialised WRF run starts.

**Files read:**
- `parame.in` — control parameters
- `wrfvar_output` (the analysis, referenced as `da_file`)
- `wrfinput_d01` (to be updated in-place)
- `wrfbdy_d01` (to be updated in-place)

**Files produced:**
- Updates `wrfinput_d01` in-place (replaces the 3D fields with the analysis)
- Updates `wrfbdy_d01` in-place (adjusts the first BDY time level)

```bash
cd $WORK

cp $HOME/WRF_demo/exercises/02_data_assimilation/parame.in $WORK/parame.in

ln -sf $WRFDA_DIR/var/da/da_update_bc.exe $WORK/

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

> **What changed in `wrfinput_d01`?**  
> The file has been updated in-place.  You can compare it against the
> Exercise 1 first-guess to see the analysis increments:
> ```bash
> ncdump -v T wrfinput_d01     | head -30   # analysis temperature
> ncdump -v T $EX1/wrfinput_d01 | head -30  # first-guess temperature
> ```

---

### 4 — `wrf.exe` — the DA-initialised forecast

Now run WRF again, but this time starting from the analysis.  The
`wrfinput_d01` file in `$WORK` has been updated by `da_update_bc.exe` and
represents the improved initial state.

```bash
cd $WORK

# Link WRF physics tables (same as Exercise 1)
for f in $WRF_DIR/run/*.TBL $WRF_DIR/run/*.asc $WRF_DIR/run/*.bin \
          $WRF_DIR/run/*.formatted $WRF_DIR/run/tr* $WRF_DIR/run/co2_trans \
          $WRF_DIR/run/MPTABLE.TBL; do
    [ -e "$f" ] && ln -sf "$f" $WORK/ || true
done

# Use the same WRF namelist as Exercise 1
cp $HOME/WRF_demo/exercises/01_basic_wrf_run/namelist.input $WORK/namelist.input

# Clean up any previous rsl files
rm -f rsl.out.* rsl.error.*

mpirun -np $MAX_CPU $WRF_DIR/main/wrf.exe
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

Compare 2-m temperature at the first output time:

```bash
ncdump -v T2 $BASE_DIR/run/ex01/wrfout_d01_2019-09-04_12:00:00 | tail -5
ncdump -v T2 $BASE_DIR/run/ex02/wrfout_d01_2019-09-04_12:00:00 | tail -5
```

Or compare the initial states directly:

```bash
ncdump -v T2 $BASE_DIR/run/ex01/wrfinput_d01 | tail -5   # free fcst IC
ncdump -v T2 $BASE_DIR/run/ex02/wrfinput_d01 | tail -5   # DA analysis IC
```

The differences between the two `wrfinput_d01` files are the **analysis
increments** — the corrections the 3D-Var system applied based on the
observations.

---

## What can go wrong — quick troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `da_wrfvar.exe` aborts with `Cannot find ob.bufr` | PREPBUFR file missing | Run `get_obs.sh` and ensure `ob.bufr` is in `$WORK` |
| `da_wrfvar.exe` aborts with `Cannot find fg` | `fg` symlink missing or broken | `ln -sf $WORK/wrfinput_d01 $WORK/fg` |
| `da_wrfvar.exe` aborts with `be.dat` error | Missing or wrong background error file | Check `ln -sf ... be.dat` is correct |
| Cost function does not decrease | No valid obs inside domain | Check `statistics` file; verify `ob.bufr` contains obs inside the WRF grid |
| `statistics` shows 0 obs used | Date mismatch between PREPBUFR and `analysis_date` | Confirm `ob.bufr` cycle matches `analysis_date` in `namelist.input.wrfda` |
| `da_update_bc.exe` aborts | `parame.in` paths wrong | Ensure `da_file`, `wrf_input`, `wrf_bdy_file` point to files in `$WORK` |
| `wrf.exe` crashes at t=0 after DA | `wrfinput_d01` / `wrfbdy_d01` inconsistency | Re-run `da_update_bc.exe`; check the log for errors |

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
