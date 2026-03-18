#!/bin/bash
# =============================================================================
# check_done.sh — Exercise 1 completion check
# =============================================================================
# Run this after finishing Exercise 1 to verify your run produced valid output.
# You must pass this check before starting Exercise 2.
#
# Usage:
#   source $HOME/WRF_demo_env/scripts/env.sh
#   bash check_done.sh
# =============================================================================

set -euo pipefail

PASS=0
FAIL=0
WORK="${BASE_DIR:-$HOME/WRF_demo_env}/run/ex01"

ok()   { echo "[PASS] $*"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $*"; FAIL=$((FAIL+1)); }

echo "========================================================================"
echo "  Exercise 1 completion check"
echo "  Working directory: $WORK"
echo "========================================================================"

# --- WPS outputs ---
[ -f "$WORK/geo_em.d01.nc" ]         && ok "geo_em.d01.nc exists"         || fail "geo_em.d01.nc not found — did geogrid.exe finish?"
ls "$WORK/GFS:"* > /dev/null 2>&1   && ok "ungrib GFS:* files exist"    || fail "FILE:* not found — did ungrib.exe finish?"
ls "$WORK/met_em.d01."*.nc > /dev/null 2>&1 && ok "met_em.d01.*.nc files exist" || fail "met_em files not found — did metgrid.exe finish?"

# --- real.exe outputs ---
[ -f "$WORK/wrfinput_d01" ]          && ok "wrfinput_d01 exists"          || fail "wrfinput_d01 not found — did real.exe finish?"
[ -f "$WORK/wrfbdy_d01" ]            && ok "wrfbdy_d01 exists"            || fail "wrfbdy_d01 not found — did real.exe finish?"

# --- wrf.exe output ---
WRF_OUT=$(ls "$WORK/wrfout_d01_"* 2>/dev/null | head -1)
if [ -n "$WRF_OUT" ]; then
    ok "wrfout_d01 file(s) found: $(ls $WORK/wrfout_d01_* | wc -l) file(s)"
else
    fail "No wrfout_d01 files found — did wrf.exe complete?"
fi

# --- Check wrf.exe actually succeeded (not just file exists) ---
if [ -f "$WORK/rsl.out.0000" ]; then
    if grep -q "SUCCESS COMPLETE WRF" "$WORK/rsl.out.0000"; then
        ok "rsl.out.0000 confirms: SUCCESS COMPLETE WRF"
    else
        fail "rsl.out.0000 does not contain 'SUCCESS COMPLETE WRF' — model may have crashed"
    fi
else
    fail "rsl.out.0000 not found — wrf.exe was not run from this directory"
fi

# --- Summary ---
echo ""
echo "========================================================================"
if [ $FAIL -eq 0 ]; then
    echo "  ALL CHECKS PASSED ($PASS/$((PASS+FAIL)))"
    echo ""
    echo "  Well done! You can now proceed to:"
    echo "  Exercise 2 — Data Assimilation with WRFDA 3D-Var"
    echo "  → $HOME/WRF_demo/exercises/02_data_assimilation/README.md"
else
    echo "  $FAIL CHECK(S) FAILED — please fix the issues above before"
    echo "  moving on to Exercise 2."
fi
echo "========================================================================"
