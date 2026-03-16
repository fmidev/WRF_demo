# Exercise 3 — Physics & Dynamics Sensitivity Run

## Prerequisites

**You must have completed Exercise 1 successfully before starting this one.**

Run the completion check now:

```bash
source $HOME/WRF_demo_env/scripts/env.sh
bash $HOME/WRF_demo/exercises/01_basic_wrf_run/check_done.sh
```

All checks must pass (especially `wrfinput_d01`, `wrfbdy_d01`, and at least
one `wrfout_d01` file).  The `wrfout` files from Exercise 1 are needed for
the comparison plot at the end of this exercise.

---

## Goal

Run WRF a second time over the **same domain, same period, and same initial
and boundary conditions** as Exercise 1, but with a **different set of
physics and dynamics options**.  Then compare the two runs side-by-side to
see how the choice of parameterisation scheme affects the forecast.

You will:

1. Set up a new working directory re-using the IC/BC from Exercise 1
2. Run `wrf.exe` with the new namelist
3. Produce a side-by-side comparison plot and discuss the differences

---

## Background — why do physics choices matter?

WRF does not simulate every atmospheric process from first principles.
Processes that occur at scales smaller than the grid spacing (convection,
turbulence, radiation, microphysics) must be **parameterised** — represented
by simplified equations that capture their bulk effect on the resolved flow.
Different parameterisation schemes make different assumptions and can produce
noticeably different forecasts even when started from identical initial
conditions.

### What changed between Exercise 1 and Exercise 3

| Setting | Exercise 1 (CONUS suite) | Exercise 3 (explicit) | Effect |
|---------|--------------------------|----------------------|--------|
| Microphysics | Thompson (suite default) | Thompson (mp=8) | Same |
| Cumulus | Tiedtke (cu=16) | Kain-Fritsch (cu=1) | Different convective triggering and mass flux |
| LW radiation | RRTM (ra_lw=3) | RRTMG (ra_lw=4) | More accurate gaseous absorption |
| SW radiation | Dudhia (ra_sw=1) | RRTMG (ra_sw=4) | More accurate solar heating |
| PBL | MYJ TKE (bl_pbl=2) | YSU (bl_pbl=1) | Non-local vs. local mixing scheme |
| Surface layer | Eta (sf_sfclay=2) | Revised MM5 (sf_sfclay=1) | Required by YSU |
| LSM | Noah-MP (sf_surface=4) | Noah (sf_surface=2) | Simpler soil/veg treatment |
| Diffusion | Full tensor (diff_opt=2) | Simple (diff_opt=1) | Less lateral mixing |
| Vertical velocity damping | Off (w_damping=0) | On (w_damping=1) | Damps spurious vertical oscillations |

The most impactful changes are the **cumulus scheme** (KF vs. Tiedtke —
affects where and when deep convection is triggered) and the **PBL scheme**
(YSU non-local vs. MYJ local TKE — affects boundary-layer depth, moisture
transport, and near-surface temperature).

---

## Directory layout

```
03_sensitivity_run/
├── README.md             ← this file
├── namelist.input        ← WRF configuration with new physics/dynamics
├── plot_comparison.py    ← side-by-side comparison plotting script
└── check_done.sh         ← run when finished
```

Working directory for this exercise: `$BASE_DIR/run/ex03/`

---

## Step-by-step walkthrough

### 1 — Set up the working directory

```bash
source $HOME/WRF_demo_env/scripts/env.sh

EX01=$BASE_DIR/run/ex01
WORK=$BASE_DIR/run/ex03
mkdir -p $WORK
cd $WORK
```

---

### 2 — Re-use the IC/BC from Exercise 1

Because the domain and start time are identical we can copy the initialisation
files produced by `real.exe` in Exercise 1 directly — no need to re-run WPS
or `real.exe`.

```bash
cp $EX01/wrfinput_d01 $WORK/
cp $EX01/wrfbdy_d01   $WORK/
```

> **Why can we do this?**  
> `wrfinput_d01` and `wrfbdy_d01` are produced by `real.exe` from the WPS
> `met_em` files.  They contain the interpolated atmospheric state and are
> completely independent of the WRF physics settings.  Only `namelist.input`
> controls which physics schemes run — the IC/BC files are identical.

---

### 3 — Copy the namelist and physics tables

```bash
cp $HOME/WRF_demo/exercises/03_sensitivity_run/namelist.input $WORK/namelist.input

# Update num_metgrid_levels to match your met_em files
# (same value you used in Exercise 1)
sed -i "s/num_metgrid_levels\s*=\s*[0-9]*/num_metgrid_levels = 34/" namelist.input

# Link all WRF physics tables (same as Exercise 1)
for f in $WRF_DIR/run/*.TBL $WRF_DIR/run/*.asc $WRF_DIR/run/*.bin \
          $WRF_DIR/run/*.formatted $WRF_DIR/run/tr* $WRF_DIR/run/co2_trans \
          $WRF_DIR/run/MPTABLE.TBL; do
    [ -e "$f" ] && ln -sf "$f" $WORK/ || true
done
```

Take a moment to look at the namelist side-by-side with the Exercise 1 version:

```bash
diff $HOME/WRF_demo/exercises/01_basic_wrf_run/namelist.input \
     $HOME/WRF_demo/exercises/03_sensitivity_run/namelist.input
```

The only differences are in `&physics` and `&dynamics`.  The domain
geometry (`&domains`) is identical, which is what makes the comparison valid.

---

### 4 — Run `wrf.exe`

```bash
cd $WORK

# Clean up any previous output
rm -f rsl.out.* rsl.error.*

mpirun -np $MAX_CPU $WRF_DIR/main/wrf.exe
```

> **Monitor progress** in a second terminal:
> ```bash
> tail -f $BASE_DIR/run/ex03/rsl.out.0000
> ```

**Check for successful completion:**
```bash
grep "SUCCESS COMPLETE WRF" rsl.out.0000
ls -lh wrfout_d01_*
```

---

### 5 — Compare the two runs

The `plot_comparison.py` script reads one wrfout file from each run and
produces a two-panel figure with:
- **Shading** — 2-m temperature (°C), same colour scale in both panels
- **Contours** — surface pressure (hPa), every 4 hPa
- **Barbs** — 10-m wind (half barb = 2.5 m/s, full barb = 5 m/s)

```bash
cd $WORK

# Compare the analysis time (t=0)
python3 $HOME/WRF_demo/exercises/03_sensitivity_run/plot_comparison.py \
    --run1   $EX01 \
    --run2   $WORK \
    --label1 "Ex01 — CONUS suite (Tiedtke/MYJ)" \
    --label2 "Ex03 — KF/RRTMG/YSU" \
    --time   0

# Compare later in the forecast (e.g. 6-hour lead time = time index 6)
python3 $HOME/WRF_demo/exercises/03_sensitivity_run/plot_comparison.py \
    --run1   $EX01 \
    --run2   $WORK \
    --label1 "Ex01 — CONUS suite (Tiedtke/MYJ)" \
    --label2 "Ex03 — KF/RRTMG/YSU" \
    --time   6
```

Each call saves a `comparison_*.png` file in the current directory.

> **What to look for:**
>
> - **Temperature differences** at t=0 should be near zero (same IC) — any
>   small differences are due to the model's initialisation balance. Larger
>   differences at t=6 and beyond reflect the physics impact.
> - **Pressure** — the schemes produce slightly different surface pressure
>   patterns as convection and boundary-layer mixing evolve differently.
> - **Wind** — barb differences, especially near convective areas, will
>   show where the two cumulus schemes trigger storms in different locations.
>
> Try plotting at t=12 and t=24 to see whether the differences grow or
> shrink over the forecast period.

---

## Things to explore further

Once you have completed the basic comparison you can deepen the experiment:

| Experiment | What to change | What to expect |
|------------|---------------|----------------|
| Turn off cumulus (cu=0) | `cu_physics = 0` | All convection explicit — may be unrealistic at 15 km |
| Try Betts-Miller-Janjic (cu=2) | `cu_physics = 2` | Very different convective intensity |
| Switch PBL to ACM2 (bl_pbl=7) | `bl_pbl_physics = 7, sf_sfclay_physics = 1` | Non-local, asymmetric scheme |
| Reduce vertical velocity damping | `w_damping = 0` | Watch for gravity-wave noise in the vertical |

For each experiment, copy the namelist, make one change at a time, re-run
`wrf.exe`, and compare with `plot_comparison.py`.

---

## What can go wrong — quick troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `wrf.exe` aborts at t=0 with physics error | `physics_suite = 'CONUS'` conflicts with explicit scheme numbers | Ensure `physics_suite = 'none'` in `&physics` |
| `wrf.exe` crashes — CFL violation | Cumulus scheme triggering strong updrafts | Reduce `time_step` or try `w_damping = 1` |
| `plot_comparison.py` errors: no wrfout in run1 | Exercise 1 wrfout not present | Verify `$EX01/wrfout_d01_*` exists |
| Plots look identical at t=0 | Expected — ICs are the same | Check t=6, t=12 for physics divergence |
| `sf_sfclay_physics` mismatch warning | YSU (bl_pbl=1) requires sfclay=1 | Already set correctly in the provided namelist |

---

## Completion check

When you have at least one `comparison_*.png` and a successful `wrfout`
from this exercise, run:

```bash
bash $HOME/WRF_demo/exercises/03_sensitivity_run/check_done.sh
```

---

*Previous exercise →* **[Exercise 1 — A Basic Real-Data WRF Run](../01_basic_wrf_run/README.md)**
