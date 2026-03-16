#!/bin/bash
# =============================================================================
# check_done.sh — Exercise 2 completion check
# =============================================================================
# Run this after finishing Exercise 2 to verify all required outputs exist.
#
# Usage:
#   source $HOME/WRF_demo_env/scripts/env.sh
#   bash check_done.sh
# =============================================================================

set -euo pipefail

PASS=0
FAIL=0
WORK="${BASE_DIR:-$HOME/WRF_demo_env}/run/ex02"

ok()   { echo "[PASS] $*"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $*"; FAIL=$((FAIL+1)); }

echo "========================================================================"
echo "  Exercise 2 completion check"
echo "  Working directory: $WORK"
echo "========================================================================"

# --- PREPBUFR observation file ---
[ -f "$WORK/ob.bufr" ] && [ -s "$WORK/ob.bufr" ] \
    && ok "ob.bufr (PREPBUFR observations) exists" \
    || fail "ob.bufr not found or empty — run get_obs.sh to download observations"

# --- da_wrfvar.exe output ---
[ -f "$WORK/wrfvar_output" ] \
    && ok "wrfvar_output (analysis) exists" \
    || fail "wrfvar_output not found — did da_wrfvar.exe finish?"

[ -f "$WORK/cost_fn" ] \
    && ok "cost_fn exists" \
    || fail "cost_fn not found — da_wrfvar.exe may not have run"

[ -f "$WORK/statistics" ] \
    && ok "statistics file exists" \
    || fail "statistics file not found"

if [ -f "$WORK/wrfda.log" ]; then
    if grep -q "wrfvar completed successfully" "$WORK/wrfda.log"; then
        ok "wrfda.log confirms: wrfvar completed successfully"
    else
        fail "wrfda.log does not confirm successful completion"
    fi
else
    fail "wrfda.log not found"
fi

# --- da_update_bc output ---
[ -f "$WORK/update_bc.log" ] \
    && ok "update_bc.log exists" \
    || fail "update_bc.log not found — did da_update_bc.exe run?"

# --- DA-initialised WRF run output ---
WRF_OUT=$(ls "$WORK/wrfout_d01_"* 2>/dev/null | head -1)
if [ -n "$WRF_OUT" ]; then
    ok "wrfout_d01 file(s) found: $(ls $WORK/wrfout_d01_* | wc -l) file(s)"
else
    fail "No wrfout_d01 files found — did wrf.exe complete?"
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

# --- Summary ---
echo ""
echo "========================================================================"
if [ $FAIL -eq 0 ]; then
    echo "  ALL CHECKS PASSED ($PASS/$((PASS+FAIL)))"
    echo ""
    echo "  Well done! You have completed Exercise 2."
    echo "  Compare your free forecast (ex01) vs DA-initialised (ex02):"
    echo "    ncdump -v T2 ${BASE_DIR}/run/ex01/wrfout_d01_2019-09-04_12:00:00"
    echo "    ncdump -v T2 ${BASE_DIR}/run/ex02/wrfout_d01_2019-09-04_12:00:00"
else
    echo "  $FAIL CHECK(S) FAILED — please fix the issues above."
fi
echo "========================================================================"
