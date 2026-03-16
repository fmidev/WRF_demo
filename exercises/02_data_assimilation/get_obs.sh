#!/bin/bash
# =============================================================================
# get_obs.sh — Download NCEP conventional observations for WRFDA Exercise 2
# =============================================================================
# Downloads the GDAS PREPBUFR conventional observation file from the NOAA
# NOMADS archive for a given analysis time.  This file contains surface,
# upper-air, aircraft, and ship observations in BUFR format and is used
# directly by da_wrfvar.exe when ob_format = 1.
#
# Only conventional observations are downloaded (prepbufr).  Satellite
# radiance BUFR files are not included — they require additional CRTM
# coefficients and sensor configuration that are beyond the scope of this
# exercise.
#
# Usage:
#   bash get_obs.sh [-n]
#
# Options:
#   -n   Dry run — print the URL and settings, do not download
#
# Output:
#   <output_dir>/ob.bufr   — PREPBUFR file ready for da_wrfvar.exe
# =============================================================================

set -euo pipefail

DRYRUN=""
while getopts "n" flag; do
    case "$flag" in
        n) DRYRUN=1 ;;
        *) echo "Usage: bash get_obs.sh [-n]"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helper: prompt for a valid integer in [min, max]
# ---------------------------------------------------------------------------
ask_integer() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local var_name="$4"
    local value=""
    while true; do
        read -rp "$prompt" value
        if [[ "$value" =~ ^[0-9]+$ ]] && \
           [ "$value" -ge "$min" ] && [ "$value" -le "$max" ]; then
            printf -v "$var_name" '%s' "$value"
            return
        fi
        echo "  Please enter a whole number between $min and $max."
    done
}

# ===========================================================================
# SECTION 1 — Analysis date and hour
# ===========================================================================
echo ""
echo "========================================================================"
echo "  NCEP Observation Download — WRF Demo Exercise 2"
echo "========================================================================"
echo ""
echo "--- Step 1: Analysis date and hour ---"
echo ""
echo "  Enter the date and hour of your DA analysis cycle."
echo "  This must match analysis_date in namelist.input.wrfda"
echo "  and time_analysis in namelist.obsproc."
echo ""
echo "  NOMADS archives GDAS PREPBUFR files for cycles at 00, 06, 12, 18 UTC."
echo "  Files are available for roughly the past 10 days on the real-time"
echo "  server.  For older dates use the NCEI archive (see note below)."
echo ""

read -rp "  Analysis date (YYYYMMDD): " ANA_DATE
while [[ ! "$ANA_DATE" =~ ^[0-9]{8}$ ]]; do
    read -rp "  Invalid format, enter YYYYMMDD: " ANA_DATE
done

echo ""
echo "  Available cycle hours: 00  06  12  18"
read -rp "  Analysis hour (UTC): " ANA_HOUR_RAW
ANA_HOUR=$(printf "%02d" "$((10#$ANA_HOUR_RAW))")
while [[ ! "$ANA_HOUR" =~ ^(00|06|12|18)$ ]]; do
    read -rp "  Must be 00, 06, 12, or 18: " ANA_HOUR_RAW
    ANA_HOUR=$(printf "%02d" "$((10#$ANA_HOUR_RAW))")
done

# ===========================================================================
# SECTION 2 — Output directory
# ===========================================================================
echo ""
echo "--- Step 2: Output directory ---"
echo ""
echo "  Where should the downloaded file be saved?"
echo "  The default places it in the Exercise 2 working directory so"
echo "  da_wrfvar.exe can find it directly."
echo ""

DEFAULT_OUT="$HOME/WRF_demo_env/run/ex02"
read -rp "  Output directory [${DEFAULT_OUT}]: " OUT_DIR_INPUT
OUT_DIR="${OUT_DIR_INPUT:-$DEFAULT_OUT}"

# ===========================================================================
# Build URL
# ===========================================================================
# Operational GDAS PREPBUFR on NOMADS real-time server
# File naming: gdas.tHHz.prepbufr.nr  (non-restricted version)
REMOTE_FILE="gdas.t${ANA_HOUR}z.prepbufr.nr"
BASE_URL="https://nomads.ncep.noaa.gov/pub/data/nccf/com/obsproc/prod/gdas.${ANA_DATE}"
URL="${BASE_URL}/${REMOTE_FILE}"
LOCAL_FILE="${OUT_DIR}/ob.bufr"

# ===========================================================================
# Confirm
# ===========================================================================
echo ""
echo "========================================================================"
echo "  Ready to download"
echo "========================================================================"
echo "  Analysis time : ${ANA_DATE} ${ANA_HOUR} UTC"
echo "  Remote file   : ${REMOTE_FILE}"
echo "  Source URL    : ${URL}"
echo "  Local file    : ${LOCAL_FILE}"
[ -n "$DRYRUN" ] && echo "  *** DRY RUN — nothing will be downloaded ***"
echo "========================================================================"
echo ""

if [ -n "$DRYRUN" ]; then
    echo "Dry run complete.  Re-run without -n to download."
    echo ""
    echo "After downloading, set ob_format = 1 in namelist.input.wrfda and"
    echo "link the file as 'ob.bufr' in your WRFDA working directory."
    exit 0
fi

read -rp "  Proceed with download? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
echo ""

mkdir -p "$OUT_DIR"

# ===========================================================================
# Download
# ===========================================================================
if [ -f "$LOCAL_FILE" ] && [ -s "$LOCAL_FILE" ]; then
    echo "[OK]  Already exists: $LOCAL_FILE ($(du -sh "$LOCAL_FILE" | cut -f1)) — skipping."
    echo "      Delete the file and re-run if you want to re-download."
    DOWNLOAD_DONE=1
else
    DOWNLOAD_DONE=0
fi

if [ "$DOWNLOAD_DONE" -eq 0 ]; then
    TMP_FILE="${LOCAL_FILE}.tmp"
    ATTEMPT=0
    SUCCESS=0

    while [ $ATTEMPT -lt 3 ]; do
        ATTEMPT=$((ATTEMPT + 1))
        echo "[DL]  Attempt $ATTEMPT — downloading ${REMOTE_FILE} ..."

        if curl -f -s -S --retry 3 --retry-delay 10 \
                -o "$TMP_FILE" "$URL" 2>&1; then
            if [ -s "$TMP_FILE" ]; then
                mv "$TMP_FILE" "$LOCAL_FILE"
                echo "[OK]  Saved: $LOCAL_FILE ($(du -sh "$LOCAL_FILE" | cut -f1))"
                SUCCESS=1
                break
            else
                echo "[WARN] Server returned an empty file on attempt $ATTEMPT."
                rm -f "$TMP_FILE"
            fi
        else
            echo "[WARN] curl failed on attempt $ATTEMPT."
            rm -f "$TMP_FILE"
        fi

        [ $ATTEMPT -lt 3 ] && sleep 15
    done

    if [ $SUCCESS -eq 0 ]; then
        echo ""
        echo "[ERROR] Failed to download ${REMOTE_FILE} after 3 attempts."
        echo ""
        echo "  Possible reasons:"
        echo "    1. The date ${ANA_DATE} is older than ~10 days — the real-time"
        echo "       NOMADS server only keeps recent files."
        echo "       For older dates, download from the NCEI archive:"
        echo "         https://www.ncei.noaa.gov/products/weather-balloon/integrated-global-radiosonde-archive"
        echo "       or request via the NCAR RDA dataset ds337.0:"
        echo "         https://rda.ucar.edu/datasets/ds337.0/"
        echo "    2. Temporary NOMADS outage — try again in a few minutes."
        echo "    3. Network connectivity issue."
        exit 1
    fi
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "========================================================================"
echo "  Download complete"
echo "========================================================================"
echo ""
echo "  File  : $LOCAL_FILE"
echo "  Size  : $(du -sh "$LOCAL_FILE" | cut -f1)"
echo ""
echo "  Next steps in Exercise 2:"
echo "    1. Make sure namelist.input.wrfda contains:"
echo "         ob_format = 1"
echo "    2. Link the file into your WRFDA working directory:"
echo "         ln -sf $LOCAL_FILE \$BASE_DIR/run/ex02/ob.bufr"
echo "    3. Run da_wrfvar.exe — it will read ob.bufr directly."
echo "       (obsproc.exe is NOT needed when using PREPBUFR directly)"
echo ""
echo "  See exercises/02_data_assimilation/README.md for full instructions."
echo "========================================================================"
