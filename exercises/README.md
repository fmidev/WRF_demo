# WRF Demo — Exercises

A collection of hands-on exercises for learning the WRF modelling system.
Each exercise must be completed in order — every exercise ends with a
`check_done.sh` script that verifies your outputs before you are allowed to
move on to the next one.

---

## Before you start

The demo environment must be installed and loaded in every terminal session
you use:

```bash
source $HOME/WRF_demo_env/scripts/env.sh
```

---

## Exercise sequence

```
Exercise 1 ──► check_done.sh ──► Exercise 2 ──► check_done.sh ──► …
```

Each exercise directory contains:

| File | Purpose |
|------|---------|
| `README.md` | Step-by-step manual walkthrough |
| `namelist.*` | Ready-to-use configuration files |
| `check_done.sh` | Completion gate — run before moving to the next exercise |

There are **no automated run scripts**.  Every command is meant to be typed
and understood by the trainee.

---

## Exercise list

| # | Directory | Topic | Requires |
|---|-----------|-------|----------|
| 1 | [`01_basic_wrf_run/`](01_basic_wrf_run/README.md) | Full WRF real-data run: geogrid → ungrib → metgrid → real → wrf | — |
| 2 | [`02_data_assimilation/`](02_data_assimilation/README.md) | WRFDA 3D-Var: obsproc → da_wrfvar → da_update_bc → wrf (analysis run) | Ex 1 done |
| 3 | [`03_sensitivity_run/`](03_sensitivity_run/README.md) | Physics & dynamics sensitivity: re-run with different schemes, compare with Ex 1 | Ex 1 done |

---

## How to use `check_done.sh`

At the end of each exercise, run:

```bash
bash $HOME/WRF_demo/exercises/NN_exercise_name/check_done.sh
```

The script will print `[PASS]` or `[FAIL]` for each required output file and
log message.  Only proceed to the next exercise when **all checks pass**.
