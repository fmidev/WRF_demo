#!/bin/bash
# =============================================================================
# get_gfs.sh — Download GFS boundary conditions for the WRF demo exercises
# =============================================================================
# Downloads GFS 0.25° GRIB2 files from the NOAA NOMADS filter server for a
# given model cycle.  Only the pressure levels, surface fields, and variables
# that WRF/WPS actually needs are requested, keeping file sizes small.
#
# The script will interactively ask for the cycle date/hour, forecast length,
# and the geographic bounding box of your domain.  All values that WPS needs
# (ref_lat, ref_lon, dx, e_we, e_sn) can be read directly from your
# namelist.wps — the script explains where to find each one.
#
# Usage:
#   bash get_gfs.sh [-n]
#
# Options:
#   -n   Dry run — print URLs and settings, do not download anything
# =============================================================================

set -euo pipefail

DRYRUN=""
while getopts "n" flag; do
    case "$flag" in
        n) DRYRUN=1 ;;
        *) echo "Usage: bash get_gfs.sh [-n]"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helper: read a value from stdin, re-prompting until it is a valid integer
# or decimal in the given range.  Accepts negative numbers.
# ---------------------------------------------------------------------------
ask_number() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local var_name="$4"
    local value=""
    while true; do
        read -rp "$prompt" value
        # Allow optional leading minus, digits, optional decimal point + digits
        if [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
            # Range check using awk for float support
            if awk -v v="$value" -v lo="$min" -v hi="$max" \
                   'BEGIN { exit !(v >= lo && v <= hi) }'; then
                printf -v "$var_name" '%s' "$value"
                return
            fi
        fi
        echo "  Please enter a number between $min and $max."
    done
}

ask_integer() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local var_name="$4"
    local value=""
    while true; do
        read -rp "$prompt" value
        if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge "$min" ] && [ "$value" -le "$max" ]; then
            printf -v "$var_name" '%s' "$value"
            return
        fi
        echo "  Please enter a whole number between $min and $max."
    done
}

# ===========================================================================
# SECTION 1 — Cycle date and hour
# ===========================================================================
echo ""
echo "========================================================================"
echo "  GFS Download — WRF Demo"
echo "========================================================================"
echo ""
echo "--- Step 1: GFS model cycle ---"
echo ""
echo "  Enter the date and hour of the GFS cycle you want to download."
echo "  This should be the same as start_date in your namelist.wps."
echo "  GFS runs at 00, 06, 12, and 18 UTC."
echo ""

read -rp "  Cycle date (YYYYMMDD) [$(date -u +%Y%m%d)]: " CYCLE_DATE
CYCLE_DATE="${CYCLE_DATE:-$(date -u +%Y%m%d)}"
while [[ ! "$CYCLE_DATE" =~ ^[0-9]{8}$ ]]; do
    read -rp "  Invalid format, enter YYYYMMDD: " CYCLE_DATE
done

echo ""
echo "  Available cycle hours: 00  06  12  18"
read -rp "  Cycle hour (UTC): " CYCLE_HOUR_RAW
CYCLE_HOUR=$(printf "%02d" "$((10#$CYCLE_HOUR_RAW))")
while [[ ! "$CYCLE_HOUR" =~ ^(00|06|12|18)$ ]]; do
    read -rp "  Must be 00, 06, 12, or 18: " CYCLE_HOUR_RAW
    CYCLE_HOUR=$(printf "%02d" "$((10#$CYCLE_HOUR_RAW))")
done

# ===========================================================================
# SECTION 2 — Forecast length and interval
# ===========================================================================
echo ""
echo "--- Step 2: Forecast length ---"
echo ""
echo "  How many hours of GFS output do you need?"
echo "  This should cover your WRF run_hours (end_date minus start_date)."
echo "  GFS output interval for WPS is typically 3 or 6 hours (interval_seconds"
echo "  in namelist.wps divided by 3600)."
echo ""

ask_integer "  Forecast length in hours [24]: " 3 240 FCST_LENGTH
FCST_LENGTH="${FCST_LENGTH:-24}"

ask_integer "  Interval between files in hours [3]: " 1 24 INTERVAL
INTERVAL="${INTERVAL:-3}"

OUT_DIR="./input_grib"
echo ""
read -rp "  Output directory [${OUT_DIR}]: " OUT_DIR_INPUT
OUT_DIR="${OUT_DIR_INPUT:-$OUT_DIR}"

# ===========================================================================
# SECTION 3 — Bounding box
# ===========================================================================
echo ""
echo "--- Step 3: Domain bounding box ---"
echo ""
echo "  GFS data will be downloaded only for a sub-region around your WRF"
echo "  domain, which keeps file sizes small."
echo ""
echo "  You need to define a bounding box (N/S/W/E) that is slightly LARGER"
echo "  than your WRF grid.  A margin of ~5–10° on each side is sufficient."
echo ""
echo "  Where to find your domain extents:"
echo "    Open your namelist.wps and look at the &geogrid section:"
echo "      ref_lat / ref_lon  — centre of the domain"
echo "      e_we, e_sn         — grid dimensions (west-east, south-north)"
echo "      dx, dy             — grid spacing in metres"
echo "    The approximate half-width in degrees is:"
echo "      (e_we * dx / 2) / 111000  (1 degree ≈ 111 km)"
echo ""
echo "  Use negative values for South latitudes and West longitudes."
echo "  Longitude range: -180 to 180"
echo ""

ask_number "  Northern boundary (latitude,  -90 to  90): "  -90  90  NORTH
ask_number "  Southern boundary (latitude,  -90 to  90): "  -90  90  SOUTH
ask_number "  Western boundary  (longitude, -180 to 180): " -180 180  WEST
ask_number "  Eastern boundary  (longitude, -180 to 180): " -180 180  EAST

# Sanity checks
if awk -v n="$NORTH" -v s="$SOUTH" 'BEGIN { exit !(n <= s) }'; then
    echo ""
    echo "[ERROR] Northern boundary ($NORTH) must be greater than southern boundary ($SOUTH)."
    exit 1
fi
if awk -v w="$WEST" -v e="$EAST" 'BEGIN { exit !(w >= e) }'; then
    echo ""
    echo "[ERROR] Western boundary ($WEST) must be less than eastern boundary ($EAST)."
    exit 1
fi

# ---------------------------------------------------------------------------
# Build the list of forecast hours to download
# ---------------------------------------------------------------------------
FCST_HOURS=()
for (( fh=0; fh<=FCST_LENGTH; fh+=INTERVAL )); do
    FCST_HOURS+=( "$fh" )
done

# ---------------------------------------------------------------------------
# Confirm before downloading
# ---------------------------------------------------------------------------
echo ""
echo "========================================================================"
echo "  Ready to download"
echo "========================================================================"
echo "  Cycle        : ${CYCLE_DATE} ${CYCLE_HOUR} UTC"
echo "  Forecast hrs : ${FCST_HOURS[*]}"
echo "  Region       : N=${NORTH} S=${SOUTH} W=${WEST} E=${EAST}"
echo "  Output dir   : ${OUT_DIR}"
echo "  Files        : ${#FCST_HOURS[@]}"
[ -n "$DRYRUN" ] && echo "  *** DRY RUN — no files will be downloaded ***"
echo "========================================================================"
echo ""

if [ -z "$DRYRUN" ]; then
    read -rp "  Proceed with download? [y/N]: " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
    echo ""
    mkdir -p "$OUT_DIR"
fi

# ---------------------------------------------------------------------------
# Build the NOMADS filter URL for a given forecast hour
# ---------------------------------------------------------------------------
build_url() {
    local fh_padded
    fh_padded=$(printf "%03d" "$1")
    local fname="gfs.t${CYCLE_HOUR}z.pgrb2.0p25.f${fh_padded}"

    # Pressure levels needed by WRF (full set of standard isobaric levels)
    local LEVS=""
    for L in 1 2 3 5 7 10 15 20 30 40 50 70 100 150 200 250 300 350 \
              400 450 500 550 600 650 700 750 800 850 900 925 950 975 1000; do
        LEVS+="&lev_${L}_mb=on"
    done

    # Surface / near-surface levels
    local SURF="&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on"
    SURF+="&lev_mean_sea_level=on&lev_entire_atmosphere=on"
    SURF+="&lev_0-0.1_m_below_ground=on&lev_0.1-0.4_m_below_ground=on"
    SURF+="&lev_0.4-1_m_below_ground=on&lev_1-2_m_below_ground=on"

    # Variables required by WPS ungrib / Vtable.GFS
    local VARS=""
    for V in HGT TMP SPFH UGRD VGRD DZDT RH PRES PRMSL MSLET \
              LAND ICEC SNOD WEASD SOILW TSOIL CNWAT \
              CAPE CIN PWAT PRATE SHTFL PEVPR TCDC; do
        VARS+="&var_${V}=on"
    done

    # Sub-region bounding box (NOMADS uses positive-east longitudes for West)
    local leftlon=$WEST
    local rightlon=$EAST
    # NOMADS filter requires longitudes in 0–360 range
    [ "$leftlon" -lt 0 ] && leftlon=$((leftlon + 360))
    [ "$rightlon" -lt 0 ] && rightlon=$((rightlon + 360))

    local REGION="&subregion=&leftlon=${leftlon}&rightlon=${rightlon}&toplat=${NORTH}&bottomlat=${SOUTH}"

    echo "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?file=${fname}${LEVS}${SURF}${VARS}${REGION}&dir=%2Fgfs.${CYCLE_DATE}%2F${CYCLE_HOUR}%2Fatmos"
}

# ---------------------------------------------------------------------------
# Download loop
# ---------------------------------------------------------------------------
FAILED=()

for FH in "${FCST_HOURS[@]}"; do
    FH_PAD=$(printf "%03d" "$FH")
    REMOTE_NAME="gfs.t${CYCLE_HOUR}z.pgrb2.0p25.f${FH_PAD}"

    # Compute valid date+hour for the output filename
    VALID_EPOCH=$(date -u -d "${CYCLE_DATE} ${CYCLE_HOUR}:00:00 UTC + ${FH} hours" +%s)
    VALID_DATE=$(date -u -d "@${VALID_EPOCH}" +%Y-%m-%d)
    VALID_HOUR=$(date -u -d "@${VALID_EPOCH}" +%H)
    LOCAL_NAME="${OUT_DIR}/gfs_${VALID_DATE}_${VALID_HOUR}.grb2"

    URL=$(build_url "$FH")

    if [ -n "$DRYRUN" ]; then
        echo "[DRY] f${FH_PAD} → ${LOCAL_NAME}"
        echo "      ${URL}"
        echo ""
        continue
    fi

    if [ -f "$LOCAL_NAME" ] && [ -s "$LOCAL_NAME" ]; then
        echo "[OK]  Already exists: $LOCAL_NAME ($(du -sh "$LOCAL_NAME" | cut -f1)) — skipping"
        continue
    fi

    echo "[DL]  f${FH_PAD} → ${LOCAL_NAME} ..."
    TMP_FILE="${LOCAL_NAME}.tmp"

    ATTEMPT=0
    SUCCESS=0
    while [ $ATTEMPT -lt 3 ]; do
        ATTEMPT=$((ATTEMPT + 1))
        if curl -f -s -S --retry 3 --retry-delay 10 \
                -o "$TMP_FILE" "$URL" 2>&1; then
            # Basic validity check: file must be non-empty and parseable as GRIB2
            if [ -s "$TMP_FILE" ]; then
                mv "$TMP_FILE" "$LOCAL_NAME"
                echo "[OK]  Saved: $LOCAL_NAME ($(du -sh "$LOCAL_NAME" | cut -f1))"
                SUCCESS=1
                break
            else
                echo "[WARN] Empty file on attempt $ATTEMPT"
                rm -f "$TMP_FILE"
            fi
        else
            echo "[WARN] curl failed on attempt $ATTEMPT"
            rm -f "$TMP_FILE"
        fi
        [ $ATTEMPT -lt 3 ] && sleep 15
    done

    if [ $SUCCESS -eq 0 ]; then
        echo "[ERR]  Failed to download f${FH_PAD} after 3 attempts"
        FAILED+=( "$REMOTE_NAME" )
    fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================================================"
if [ -n "$DRYRUN" ]; then
    echo "  Dry run complete. Re-run without -n to download."
elif [ ${#FAILED[@]} -eq 0 ]; then
    echo "  All files downloaded successfully."
    echo ""
    echo "  Files in ${OUT_DIR}:"
    ls -lh "${OUT_DIR}"/gfs_*.grb2 2>/dev/null || echo "  (none)"
    echo ""
    echo "  Next step: run geogrid.exe, then ungrib.exe using these files."
    echo "  See exercises/01_basic_wrf_run/README.md"
else
    echo "  Download finished with ${#FAILED[@]} failure(s):"
    for f in "${FAILED[@]}"; do echo "    - $f"; done
    echo ""
    echo "  Check your internet connection and try again."
    exit 1
fi
echo "========================================================================"
