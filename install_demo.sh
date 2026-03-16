#!/bin/bash
# ===============================================================================
#                  WRF Demo / Training Environment Installation Script
# ===============================================================================
# This script installs a minimal WRF environment for training and demo purposes.
# It compiles all required libraries and WRF/WPS/WRFDA binaries, links the
# executables into a central bin/ directory, and writes a simple env.sh.
#
# What is installed:
#   Libraries : zlib, OpenMPI, szip, HDF5, netCDF-C, netCDF-Fortran,
#               libjpeg, libpng, jasper
#   WRF system components : WRF, WPS, WRFDA
#   Python packages       : numpy, matplotlib, netCDF4, cartopy
#
# What is NOT included (compared with the operational script):
#   UPP, NCEPlibs, CRTM, RStudio, Shiny, verification tools,
#   crontab setup, git repository tracking.
# ===============================================================================

# --- Package version configuration ---
export WRF_VERSION="4.7.1"
export WPS_VERSION="4.6.0"

export ZLIB_VERSION="1.3.2"
export OPENMPI_VERSION="5.0.3"
export SZIP_VERSION="2.1.1"
export HDF5_VERSION="1.14.4-3"
export NETCDF_C_VERSION="4.9.3"
export NETCDF_FORTRAN_VERSION="4.6.2"
export JPEG_VERSION="9f"
export LIBPNG_VERSION="1.6.48"
export JASPER_VERSION="4.2.5"

# Start timing
start_time=$(date +%s)
echo "Starting WRF demo installation at $(date)"

echo "================================================================================"
echo "            WRF Demo / Training Environment Installation Script                  "
echo "================================================================================"

# --- Grant temporary sudo rights ---
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/temp_wrf_demo_install > /dev/null
trap 'sudo rm -f /etc/sudoers.d/temp_wrf_demo_install' EXIT

# --- Installation directory ---
echo -n "Enter the installation directory [default: /home/$USER/WRF_demo_env]: "
read user_base_dir
if [ -z "$user_base_dir" ]; then
    export BASE=/home/$USER/WRF_demo_env
    echo "Using default: $BASE"
else
    export BASE=$user_base_dir
    echo "Using: $BASE"
fi

mkdir -p "$BASE"/{libraries,bin,run,logs,install_logs,tmp,WPS_GEOG}

# --- System packages ---
echo "Installing required system packages..."
sudo dnf config-manager --set-enabled crb -q
sudo dnf makecache -y -q
sudo dnf install -y epel-release gcc gfortran g++ wget tar perl m4 \
    libcurl-devel csh ksh cmake bc time openssl-devel libxml2-devel \
    eccodes eccodes-devel proj proj-devel nco wgrib2 \
    python3 python3-pip python3-devel -q
sudo dnf update -y -q
echo "[OK] System packages installed."

# --- Python packages for visualisation ---
echo "Installing Python visualisation packages..."
pip3 install --quiet --upgrade pip
pip3 install --quiet \
    numpy \
    matplotlib \
    netCDF4 \
    cartopy \
    Pillow
echo "[OK] Python packages installed."

# --- CPU detection ---
CPU_COUNT=$(nproc)
MAX_CPU=$((CPU_COUNT - 1))
[ $MAX_CPU -lt 1 ] && MAX_CPU=1
echo "Detected $CPU_COUNT CPU cores, will use up to $MAX_CPU for compilation."

export CC=gcc
export CXX=g++
export FC=gfortran

# -----------------------------------------------------------------------
# Helper: check an explicit exit code against a log file
# Usage: check_exit $? "$log_file" "step description"
# -----------------------------------------------------------------------
check_exit() {
    local code=$1
    local log_file=$2
    local step=${3:-"step"}
    if [ "$code" -ne 0 ]; then
        echo "[ERROR] ERROR: $step failed (exit $code). Check $log_file for details."
        exit 1
    fi
}

# -----------------------------------------------------------------------
# Helper: download, extract, configure, make, install a library
# -----------------------------------------------------------------------
install_library() {
    local url=$1
    local version_dir_name=$2
    local generic_name=$3
    local configure_args=$4
    local file_name=${url##*/}
    local log_file="$BASE/install_logs/${generic_name}_install.log"

    # Skip if already installed (symlink present)
    if [ -L "$BASE/libraries/$generic_name" ]; then
        echo "[OK] $generic_name already installed. Skipping."
        return
    fi

    echo "[--] Installing $generic_name... (log: $log_file)"
    cd "$BASE/libraries"

    # Download
    if [ ! -f "$file_name" ]; then
        echo "   Downloading $file_name..."
        wget --progress=bar:force "$url" -O "$file_name" >> "$log_file" 2>&1
        check_exit $? "$log_file" "Download of $file_name"
    else
        echo "   $file_name already downloaded. Skipping download."
    fi

    # Extract
    echo "   Extracting $file_name..."
    tar -xf "$file_name" >> "$log_file" 2>&1
    check_exit $? "$log_file" "Extraction of $file_name"

    # Verify directory exists before cd
    if [ ! -d "$BASE/libraries/$version_dir_name" ]; then
        echo "[ERROR] ERROR: Expected directory $BASE/libraries/$version_dir_name not found after extraction."
        echo "   Check $log_file and verify the tarball extracts to $version_dir_name."
        exit 1
    fi

    echo "   Configuring $generic_name..."

    if [ "$generic_name" = "jasper" ]; then
        # jasper uses CMake and forbids in-source builds - build dir must be outside source tree
        mkdir -p "$BASE/libraries/${version_dir_name}-build"
        cd "$BASE/libraries/${version_dir_name}-build"
        cmake "$BASE/libraries/$version_dir_name" \
            -DCMAKE_INSTALL_PREFIX="$BASE/libraries/$version_dir_name/install" \
            -DJAS_ENABLE_SHARED=ON \
            >> "$log_file" 2>&1
        check_exit $? "$log_file" "cmake configure jasper"
        make -j"$MAX_CPU" >> "$log_file" 2>&1
        check_exit $? "$log_file" "make jasper"
        make install >> "$log_file" 2>&1
        check_exit $? "$log_file" "make install jasper"
        cd "$BASE/libraries"
    else
        cd "$BASE/libraries/$version_dir_name"
        mkdir -p install
        eval ./configure --prefix="$BASE/libraries/$version_dir_name/install" $configure_args >> "$log_file" 2>&1
        check_exit $? "$log_file" "configure $generic_name"
        make -j"$MAX_CPU" >> "$log_file" 2>&1
        check_exit $? "$log_file" "make $generic_name"
        make install >> "$log_file" 2>&1
        check_exit $? "$log_file" "make install $generic_name"
        cd "$BASE/libraries"
    fi

    ln -sf "$version_dir_name" "$generic_name"
    echo "[OK] $generic_name installed successfully."
}

# -----------------------------------------------------------------------
# Install libraries
# -----------------------------------------------------------------------
install_library "https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz" \
    "zlib-${ZLIB_VERSION}" "zlib" ""

install_library "https://download.open-mpi.org/release/open-mpi/v${OPENMPI_VERSION%.*}/openmpi-${OPENMPI_VERSION}.tar.gz" \
    "openmpi-${OPENMPI_VERSION}" "openmpi" \
    "--with-zlib=$BASE/libraries/zlib/install"

export PATH="$BASE/libraries/openmpi/install/bin:$PATH"

install_library "https://support.hdfgroup.org/ftp/lib-external/szip/${SZIP_VERSION}/src/szip-${SZIP_VERSION}.tar.gz" \
    "szip-${SZIP_VERSION}" "szip" ""

install_library "https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-${HDF5_VERSION%.*}/hdf5-${HDF5_VERSION%%-*}/src/hdf5-${HDF5_VERSION}.tar.gz" \
    "hdf5-${HDF5_VERSION}" "hdf5" \
    "--with-zlib=$BASE/libraries/zlib/install/ \
     --with-szlib=$BASE/libraries/szip/install/ \
     --enable-fortran"

install_library "https://downloads.unidata.ucar.edu/netcdf-c/${NETCDF_C_VERSION}/netcdf-c-${NETCDF_C_VERSION}.tar.gz" \
    "netcdf-c-${NETCDF_C_VERSION}" "netcdf-c" \
    "--enable-netcdf-4 \
     LDFLAGS=\"-L$BASE/libraries/hdf5/install/lib\" \
     CPPFLAGS=\"-I$BASE/libraries/hdf5/install/include\" \
     CC=gcc"

export LD_LIBRARY_PATH="$BASE/libraries/netcdf-c/install/lib:$LD_LIBRARY_PATH"

install_library "https://downloads.unidata.ucar.edu/netcdf-fortran/${NETCDF_FORTRAN_VERSION}/netcdf-fortran-${NETCDF_FORTRAN_VERSION}.tar.gz" \
    "netcdf-fortran-${NETCDF_FORTRAN_VERSION}" "netcdf-fortran" \
    "LDFLAGS=\"-L$BASE/libraries/netcdf-c/install/lib/\" \
     CPPFLAGS=\"-I$BASE/libraries/netcdf-c/install/include/\" \
     FC=gfortran F77=gfortran"

# WRF configure requires netcdf.inc and Fortran modules in the same NETCDF prefix
# as the C headers - merge netcdf-fortran includes and libs into netcdf-c install
echo "Merging netcdf-fortran headers and libs into netcdf-c install..."
cp -n  "$BASE/libraries/netcdf-fortran/install/include/"* "$BASE/libraries/netcdf-c/install/include/"
cp -rn "$BASE/libraries/netcdf-fortran/install/lib/."   "$BASE/libraries/netcdf-c/install/lib/"
echo "[OK] netcdf-fortran merged."

install_library "http://www.ijg.org/files/jpegsrc.v${JPEG_VERSION}.tar.gz" \
    "jpeg-${JPEG_VERSION}" "jpeg" ""

install_library "https://github.com/pnggroup/libpng/archive/refs/tags/v${LIBPNG_VERSION}.tar.gz" \
    "libpng-${LIBPNG_VERSION}" "libpng" ""

install_library "https://github.com/jasper-software/jasper/releases/download/version-${JASPER_VERSION}/jasper-${JASPER_VERSION}.tar.gz" \
    "jasper-${JASPER_VERSION}" "jasper" ""

# -----------------------------------------------------------------------
# WRF
# -----------------------------------------------------------------------
if [ ! -d "$BASE/WRF" ]; then
    echo "[--] Installing WRF ${WRF_VERSION}..."
    cd "$BASE"

    if [ -f "$BASE/tmp/v${WRF_VERSION}_WRF.tar.gz" ]; then
        echo "   Using cached tarball."
        cp "$BASE/tmp/v${WRF_VERSION}_WRF.tar.gz" "v${WRF_VERSION}.tar.gz"
    else
        wget --progress=bar:force "https://github.com/wrf-model/WRF/releases/download/v${WRF_VERSION}/v${WRF_VERSION}.tar.gz"
        cp "v${WRF_VERSION}.tar.gz" "$BASE/tmp/v${WRF_VERSION}_WRF.tar.gz"
    fi

    tar -xf "v${WRF_VERSION}.tar.gz"
    mv "WRFV${WRF_VERSION}" WRF
    cd WRF

    export WRF_EM_CORE=1
    export WRF_DA_CORE=0
    export NETCDF="$BASE/libraries/netcdf-c/install"
    export NETCDF4=1
    export HDF5="$BASE/libraries/hdf5/install"
    export jasper="$BASE/libraries/jasper/install"
    export JASPERLIB="$BASE/libraries/jasper/install/lib"
    export JASPERINC="$BASE/libraries/jasper/install/include"
    export WRFIO_NCD_LARGE_FILE_SUPPORT=1

    echo "[--] Configuring WRF (option 34 = dmpar GNU)..."
    echo 34 | ./configure

    echo "[==]  Compiling WRF... (log: $BASE/WRF/compile.log)"
    ./compile em_real > compile.log 2>&1
    grep -E 'Compil|Error|SUCCESS' compile.log || true

    cd "$BASE"
    rm -f "v${WRF_VERSION}.tar.gz"

    if [ ! -f "$BASE/WRF/main/wrf.exe" ] || [ ! -f "$BASE/WRF/main/real.exe" ]; then
        echo "[ERROR] ERROR: WRF executables not found. Compilation may have failed."
        exit 1
    fi
    echo "[OK] WRF compiled successfully."
else
    echo "[OK] WRF already installed. Skipping."
fi

# -----------------------------------------------------------------------
# WPS
# -----------------------------------------------------------------------
if [ ! -d "$BASE/WPS" ]; then
    echo "[--] Installing WPS ${WPS_VERSION}..."
    cd "$BASE"

    if [ -f "$BASE/tmp/v${WPS_VERSION}_WPS.tar.gz" ]; then
        echo "   Using cached tarball."
        cp "$BASE/tmp/v${WPS_VERSION}_WPS.tar.gz" "v${WPS_VERSION}.tar.gz"
    else
        wget --progress=bar:force "https://github.com/wrf-model/WPS/archive/refs/tags/v${WPS_VERSION}.tar.gz"
        cp "v${WPS_VERSION}.tar.gz" "$BASE/tmp/v${WPS_VERSION}_WPS.tar.gz"
    fi

    tar -xf "v${WPS_VERSION}.tar.gz"
    mv "WPS-${WPS_VERSION}" WPS
    cd WPS

    export jasper="$BASE/libraries/jasper/install"
    export JASPERLIB="$BASE/libraries/jasper/install/lib"
    export JASPERINC="$BASE/libraries/jasper/install/include"
    export WRF_DIR="$BASE/WRF"
    export NETCDF="$BASE/libraries/netcdf-c/install"

    echo "[--] Configuring WPS (option 3 = dmpar GNU)..."
    echo 3 | ./configure
    sed -i "/COMPRESSION_LIBS/s|=.*|= -L$BASE/libraries/jasper/install/lib -L$BASE/libraries/libpng/install/lib -L$BASE/libraries/zlib/install/lib -ljasper -lpng -lz|" configure.wps
    sed -i "/COMPRESSION_INC/s|=.*|= -I$BASE/libraries/jasper/install/include -I$BASE/libraries/libpng/install/include -I$BASE/libraries/zlib/install/include|" configure.wps

    echo "[==]  Compiling WPS... (log: $BASE/WPS/compile.log)"
    ./compile > compile.log 2>&1
    grep -E 'Compil|Error|SUCCESS' compile.log || true

    cd "$BASE"
    rm -f "v${WPS_VERSION}.tar.gz"

    if [ ! -f "$BASE/WPS/geogrid.exe" ] || [ ! -f "$BASE/WPS/metgrid.exe" ] || [ ! -f "$BASE/WPS/ungrib.exe" ]; then
        echo "[ERROR] ERROR: WPS executables not found. Compilation may have failed."
        exit 1
    fi
    echo "[OK] WPS compiled successfully."
else
    echo "[OK] WPS already installed. Skipping."
fi

# -----------------------------------------------------------------------
# WRFDA
# -----------------------------------------------------------------------
if [ ! -d "$BASE/WRFDA" ]; then
    echo "[--] Installing WRFDA ${WRF_VERSION}..."
    cd "$BASE"

    if [ -f "$BASE/tmp/v${WRF_VERSION}_WRF.tar.gz" ]; then
        echo "   Using cached tarball."
        cp "$BASE/tmp/v${WRF_VERSION}_WRF.tar.gz" "v${WRF_VERSION}.tar.gz"
    else
        wget --progress=bar:force "https://github.com/wrf-model/WRF/releases/download/v${WRF_VERSION}/v${WRF_VERSION}.tar.gz"
        cp "v${WRF_VERSION}.tar.gz" "$BASE/tmp/v${WRF_VERSION}_WRF.tar.gz"
    fi

    tar -xf "v${WRF_VERSION}.tar.gz"
    mv "WRFV${WRF_VERSION}" WRFDA
    cd WRFDA

    export NETCDF="$BASE/libraries/netcdf-c/install"
    export NETCDF4=1
    export HDF5="$BASE/libraries/hdf5/install"
    export WRFIO_NCD_LARGE_FILE_SUPPORT=1

    echo "[--] Configuring WRFDA (option 34 = dmpar GNU)..."
    echo 34 | ./configure wrfda

    echo "[==]  Compiling WRFDA... (log: $BASE/WRFDA/compile.log)"
    ./compile all_wrfvar > compile.log 2>&1
    grep -E 'Compil|Error|SUCCESS' compile.log || true

    cd "$BASE"
    rm -f "v${WRF_VERSION}.tar.gz"

    if [ ! -f "$BASE/WRFDA/var/da/da_wrfvar.exe" ] || [ ! -f "$BASE/WRFDA/var/da/da_update_bc.exe" ]; then
        echo "[ERROR] ERROR: WRFDA executables not found. Compilation may have failed."
        exit 1
    fi
    echo "[OK] WRFDA compiled successfully."
else
    echo "[OK] WRFDA already installed. Skipping."
fi

# -----------------------------------------------------------------------
# Link executables into $BASE/bin
# -----------------------------------------------------------------------
echo "[>>] Linking executables into $BASE/bin ..."

link_exe() {
    local src=$1
    local name=$2
    if [ -f "$src" ]; then
        ln -sf "$src" "$BASE/bin/$name"
        echo "   Linked: $name -> $src"
    else
        echo "   [WARN]  WARNING: $src not found, skipping link."
    fi
}

# WRF
link_exe "$BASE/WRF/main/wrf.exe"        "wrf.exe"
link_exe "$BASE/WRF/main/real.exe"       "real.exe"
link_exe "$BASE/WRF/main/ndown.exe"      "ndown.exe"
link_exe "$BASE/WRF/main/tc.exe"         "tc.exe"

# WPS
link_exe "$BASE/WPS/geogrid.exe"         "geogrid.exe"
link_exe "$BASE/WPS/metgrid.exe"         "metgrid.exe"
link_exe "$BASE/WPS/ungrib.exe"          "ungrib.exe"

# WRFDA
link_exe "$BASE/WRFDA/var/da/da_wrfvar.exe"   "da_wrfvar.exe"
link_exe "$BASE/WRFDA/var/da/da_update_bc.exe" "da_update_bc.exe"

echo "[OK] Executables linked."

# -----------------------------------------------------------------------
# Download WPS geographical static dataset
# -----------------------------------------------------------------------
if [ -z "$(ls -A "$BASE/WPS_GEOG")" ]; then
    echo "[DL] Downloading WPS geographical static dataset..."
    cd "$BASE/WPS_GEOG"

    if [ ! -f "geog_complete.tar.gz" ]; then
        echo "   Downloading geog_complete.tar.gz (this is large, ~30 GB)..."
        wget --progress=bar:force https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_complete.tar.gz
    else
        echo "   geog_complete.tar.gz already downloaded. Skipping."
    fi

    if [ ! -f "geog_high_res_mandatory.tar.gz" ]; then
        echo "   Downloading geog_high_res_mandatory.tar.gz..."
        wget --progress=bar:force https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_high_res_mandatory.tar.gz
    else
        echo "   geog_high_res_mandatory.tar.gz already downloaded. Skipping."
    fi

    echo "   Extracting geographical dataset..."
    tar -zxf geog_complete.tar.gz --strip-components=1
    tar -zxf geog_high_res_mandatory.tar.gz --strip-components=1
    echo "[OK] Geographical dataset downloaded and extracted."
else
    echo "[OK] Geographical dataset already present in $BASE/WPS_GEOG. Skipping."
fi

# -----------------------------------------------------------------------
# Write env.sh
# -----------------------------------------------------------------------
echo "[WR] Writing $BASE/scripts/env.sh ..."
mkdir -p "$BASE/scripts"

cat > "$BASE/scripts/env.sh" << ENVEOF
#!/bin/bash
# ===============================================================================
# WRF Demo / Training Environment - Path and Variable Configuration
# ===============================================================================
# Source this file before running any WRF component:
#   source \$BASE/scripts/env.sh
# ===============================================================================

# --- Base ---
export BASE_DIR=$BASE
export LIB_DIR=\$BASE_DIR/libraries

# --- Library paths ---
export OPENMPI=\$LIB_DIR/openmpi/install
export NETCDF=\$LIB_DIR/netcdf-c/install
export HDF5=\$LIB_DIR/hdf5/install
export jasper=\$LIB_DIR/jasper/install
export JASPERLIB=\$LIB_DIR/jasper/install/lib
export JASPERINC=\$LIB_DIR/jasper/install/include

# --- Runtime paths ---
export PATH="\$BASE_DIR/bin:\$OPENMPI/bin:\$NETCDF/bin:\$PATH"
export LD_LIBRARY_PATH="\$NETCDF/lib:\$JASPERLIB:\$HDF5/lib:\$OPENMPI/lib:\$LIB_DIR/zlib/install/lib:\$LD_LIBRARY_PATH"

# --- Model source directories (for reference / namelists) ---
export WRF_DIR=\$BASE_DIR/WRF
export WPS_DIR=\$BASE_DIR/WPS
export WRFDA_DIR=\$BASE_DIR/WRFDA

# --- NetCDF / WRF compile-time flags ---
export NETCDF4=1
export WRFIO_NCD_LARGE_FILE_SUPPORT=1

# --- Static geographical data (used in WPS namelist.wps geog_data_path) ---
export GEOG_DATA_PATH=\$BASE_DIR/WPS_GEOG

# --- Run and output directories ---
export RUN_DIR=\$BASE_DIR/run
export LOG_DIR=\$BASE_DIR/logs

# --- Resource limits ---
ulimit -s unlimited

echo "WRF demo environment loaded. Binaries are in: \$BASE_DIR/bin"
ENVEOF

chmod +x "$BASE/scripts/env.sh"
echo "[OK] env.sh written."

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
end_time=$(date +%s)
runtime=$((end_time - start_time))
hours=$((runtime / 3600))
minutes=$(( (runtime % 3600) / 60 ))
seconds=$((runtime % 60))

cat << SUMMARY
================================================================================
              WRF DEMO / TRAINING ENVIRONMENT INSTALLED SUCCESSFULLY
================================================================================

Installation directory : $BASE
Executables            : $BASE/bin/
Source code            : $BASE/WRF/, $BASE/WPS/, $BASE/WRFDA/
Libraries              : $BASE/libraries/
Static geo data        : $BASE/WPS_GEOG/
Environment script     : $BASE/scripts/env.sh
Run directory          : $BASE/run/
Logs                   : $BASE/logs/

QUICK START
   1. Load the environment:
        source $BASE/scripts/env.sh

   2. Run a component:
        cd $BASE/run
        geogrid.exe

   3. Available executables in $BASE/bin/:
        wrf.exe          - WRF model
        real.exe         - WRF real-data initialisation
        ndown.exe        - WRF nesting / downscaling
        geogrid.exe      - WPS geographical pre-processing
        metgrid.exe      - WPS meteorological pre-processing
        ungrib.exe       - WPS GRIB extraction
        da_wrfvar.exe    - WRFDA variational assimilation
        da_update_bc.exe - WRFDA lateral boundary update

================================================================================
SUMMARY

echo "[T] Installation completed in ${hours}h ${minutes}m ${seconds}s"
