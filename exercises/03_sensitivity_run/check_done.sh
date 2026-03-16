#!/bin/bash
# =============================================================================
# check_done.sh — Exercise 3 completion check
# =============================================================================
# Run this after finishing Exercise 3 to verify all required outputs exist.
#
# Usage:
#   source $HOME/WRF_demo_env/scripts/env.sh
#   bash $HOME/WRF_demo/exercises/03_sensitivity_run/check_done.sh
# =============================================================================

set -euo pipefail

PASS=0
FAIL=0
WORK="${BASE_DIR:-$HOME/WRF_demo_env}/run/ex03"
EX01="${BASE_DIR:-$HOME/WRF_demo_env}/run/ex01"

ok()   { echo "[PASS] $*"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $*"; FAIL=$((FAIL+1)); }

echo "========================================================================"
echo "  Exercise 3 completion check"
echo "  Working directory: $WORK"
echo "========================================================================"

# --- Ex01 outputs (needed for comparison plot) ---
EX01_OUT=$(ls "$EX01/wrfout_d01_"* 2>/dev/null | head -1)
if [ -n "$EX01_OUT" ]; then
    ok "Exercise 1 wrfout found (needed for comparison): $(basename $EX01_OUT)"
else
    fail "No Exercise 1 wrfout_d01 found in $EX01 — complete Exercise 1 first"
fi

# --- Ex03 WRF output ---
EX03_OUT=$(ls "$WORK/wrfout_d01_"* 2>/dev/null | head -1)
if [ -n "$EX03_OUT" ]; then
    ok "wrfout_d01 file(s) found: $(ls $WORK/wrfout_d01_* | wc -l) file(s)"
else
    fail "No wrfout_d01 files found in $WORK — did wrf.exe complete?"
fi

if [ -f "$WORK/rsl.out.0000" ]; then
    if grep -q "SUCCESS COMPLETE WRF" "$WORK/rsl.out.0000"; then
        ok "rsl.out.0000 confirms: SUCCESS COMPLETE WRF"
    else
        fail "rsl.out.0000 does not contain 'SUCCESS COMPLETE WRF'"
    fi
else
    fail "rsl.out.0000 not found — wrf.exe was not run"
fi

# --- Comparison plot ---
PLOT=$(ls "$WORK/comparison_"*.png 2>/dev/null | head -1)
if [ -n "$PLOT" ]; then
    ok "Comparison plot found: $(basename $PLOT)"
else
    fail "No comparison_*.png found in $WORK — run plot_comparison.py"
fi

# --- Summary ---
echo ""
echo "========================================================================"
if [ $FAIL -eq 0 ]; then
    echo "  ALL CHECKS PASSED ($PASS/$PASS)"
    echo ""
    echo "  Well done — you have completed Exercise 3!"
    echo "  You can now explore further by changing other physics or dynamics"
    echo "  options in namelist.input and re-running the sensitivity experiment."
    echo "========================================================================"
    exit 0
else
    echo "  $FAIL CHECK(S) FAILED  ($PASS passed, $FAIL failed)"
    echo ""
    echo "  Fix the failures above before marking this exercise complete."
    echo "========================================================================"
    exit 1
fi
