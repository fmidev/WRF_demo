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

| Setting | Exercise 1 | Exercise 3 | Effect |
|---------|------------|------------|--------|
| Microphysics | Thompson (mp=8) | Thompson (mp=8) | Same |
| Cumulus | Kain-Fritsch (cu=1) | Kain-Fritsch (cu=1) | Same |
| LW radiation | RRTMG (ra_lw=4) | RRTMG (ra_lw=4) | Same |
| SW radiation | RRTMG (ra_sw=4) | RRTMG (ra_sw=4) | Same |
| PBL | YSU (bl_pbl=1) | YSU (bl_pbl=1) | Same |
| Surface layer | Revised MM5 (sf_sfclay=1) | Revised MM5 (sf_sfclay=1) | Same |
| LSM | Noah (sf_surface=2) | Noah (sf_surface=2) | Same |
| Diffusion | Full tensor (diff_opt=2) | Simple (diff_opt=1) | Less lateral mixing |
| km_opt | 3-D TKE (km_opt=4) | Constant K (km_opt=1) | Simpler turbulent diffusion |
| Vertical velocity damping | On (w_damping=1) | On (w_damping=1) | Same |

The differences between Exercise 1 and Exercise 3 are purely in **dynamics**:
Exercise 1 uses the full diffusion tensor (`diff_opt=2`) with 3-D TKE-based
eddy diffusivity (`km_opt=4`), while Exercise 3 uses simple horizontal diffusion
(`diff_opt=1`) with a constant eddy diffusion coefficient (`km_opt=1`).
This lets you isolate the effect of turbulent diffusion treatment on the forecast.

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
cp $EX01/wrfinput_d01  $WORK/
cp $EX01/wrfbdy_d01    $WORK/
cp $EX01/wrflowinp_d01 $WORK/
```

> **Why can we do this?**  
> `wrfinput_d01` and `wrfbdy_d01` are produced by `real.exe` from the WPS
> `met_em` files.  They contain the interpolated atmospheric state and are
> completely independent of the WRF physics settings.  Only `namelist.input`
> controls which physics schemes run — the IC/BC files are identical.  
> `wrflowinp_d01` carries time-varying SST/sea-ice updates and is required
> because `sst_update = 1` in the namelist.

---

### 3 — Copy the namelist and physics tables

Copy the template namelist to `$WORK` and edit it there.  Update the dates and
domain parameters to match your Exercise 1 `namelist.input`:

```bash
cp $HOME/WRF_demo/exercises/03_sensitivity_run/namelist.input $WORK/namelist.input
nano $WORK/namelist.input   # or your preferred editor
```

Update these parameters in `&time_control` and `&domains` to match Exercise 1:

| Parameter | Where to get the value |
|-----------|------------------------|
| `start_year/month/day/hour` | Your Exercise 1 `namelist.input` |
| `end_year/month/day/hour` | Your Exercise 1 `namelist.input` |
| `run_days` / `run_hours` | Same run length as Exercise 1 |
| `e_we` / `e_sn` / `e_vert` | Same grid dimensions as Exercise 1 |
| `dx` / `dy` | Same grid spacing as Exercise 1 |
| `num_metgrid_levels` | Same as Exercise 1 (from `ncdump -h met_em.*.nc`) |
| `time_step` | Same as Exercise 1 (rule of thumb: dx_km × 6) |

```bash
# Link all WRF physics tables and data files (same as Exercise 1)
# Exclude namelist.input — that is managed manually in $WORK
for f in $WRF_DIR/run/*; do
    [[ -f "$f" && "$(basename $f)" != "namelist.input" ]] && ln -sf "$f" $WORK/ || true
done
```

Take a moment to look at the namelist side-by-side with the Exercise 1 version:

```bash
diff $EX01/namelist.input $WORK/namelist.input
```

The only differences should be in `&dynamics` (`diff_opt`, `km_opt`).
The domain geometry (`&domains`) and physics schemes (`&physics`) must be
identical to Exercise 1 for the comparison to be valid.

---

### 4 — Run `wrf.exe`

```bash
cd $WORK

# Clean up any previous output
rm -f rsl.out.* rsl.error.*

mpirun -np 4 $WRF_DIR/main/wrf.exe
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
    --label1 "Ex01 — full diffusion tensor (diff_opt=2, km_opt=4)" \
    --label2 "Ex03 — simple diffusion (diff_opt=1, km_opt=1)" \
    --time   0

# Compare later in the forecast (e.g. 6-hour lead time = time index 6)
python3 $HOME/WRF_demo/exercises/03_sensitivity_run/plot_comparison.py \
    --run1   $EX01 \
    --run2   $WORK \
    --label1 "Ex01 — full diffusion tensor (diff_opt=2, km_opt=4)" \
    --label2 "Ex03 — simple diffusion (diff_opt=1, km_opt=1)" \
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
| Full diffusion tensor | `diff_opt = 2, km_opt = 4` | Closer to Ex01 — more lateral mixing near terrain |
| Turn off w_damping | `w_damping = 0` | Watch for gravity-wave noise in vertical velocity |
| Increase 6th-order diffusion | `diff_6th_opt = 2, diff_6th_factor = 0.12` | Damps small-scale computational noise |
| Change cumulus scheme | `cu_physics = 2` (Betts-Miller-Janjic) | Different convective intensity and rainfall |
| Switch PBL to ACM2 | `bl_pbl_physics = 7, sf_sfclay_physics = 1` | Non-local asymmetric scheme — compare BL depth |

For each experiment, copy the namelist, make one change at a time, re-run
`wrf.exe`, and compare with `plot_comparison.py`.

---

## What can go wrong — quick troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `wrf.exe` aborts at t=0 with physics error | `physics_suite` not `'none'` | Ensure `physics_suite = 'none'` in `&physics` |
| `wrf.exe` crashes — CFL violation | Time step too large for grid spacing | Reduce `time_step` (rule of thumb: `dx_km × 6`) |
| `wrf.exe` fatal: `missing file for = auxinput4` | `wrflowinp_d01` not in run directory | `cp $EX01/wrflowinp_d01 $WORK/` |
| `wrf.exe` fatal: `CAMtr_volume_mixing_ratio does not exist` | Extension-less data file not linked | Re-run the full link loop: `for f in $WRF_DIR/run/*; do [[ -f "$f" && "$(basename $f)" != "namelist.input" ]] && ln -sf "$f" $WORK/; done` |
| `wrf.exe` fatal: `RRTMG_LW_DATA`/`RRTMG_SW_DATA` not found | Extension-less RRTMG data file not linked | Included in the loop above — re-run it |
| `plot_comparison.py` errors: no wrfout in run1 | Exercise 1 wrfout not present | Verify `$EX01/wrfout_d01_*` exists |
| Plots look identical at t=0 | Expected — ICs are the same | Check t=6, t=12 for dynamics divergence |
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
