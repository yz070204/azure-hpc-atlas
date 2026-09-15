# Reproducible WRF build

Do not compare binaries without a build manifest.

## Calibrated benchmark build

```text
Source: https://github.com/wrf-model/WRF.git
Tag: v4.4.2
Commit: 6233639c599119e76fca17dba9ea211af53a0ba9
Compiler: GCC/GFortran 13.3.0
MPI: Open MPI 5.0.10
NetCDF-C: 4.9.2
NetCDF-Fortran: 4.5.4
Configure: GNU dmpar option 34, basic nesting option 1
FCOPTIM: -O3 -march=znver4 -Ofast -ftree-vectorize -funroll-loops
```

Observed winning `wrf.exe` SHA-256:

```text
fdbe76eb664a59de4cf73a8a8b6aa70d8f3821a7c0d2d4a907e4e6647da3716d
```

The checksum applies only to that exact build environment; a different path,
linker, library, or compiler may legitimately produce another checksum.
These versions and paths are calibration provenance, not prerequisites. Azure
HPC base images can replace MPI, compilers, libraries, modules, and installation
prefixes.

## Discover the current image stack

Do this for every new image or rebuilt VM before selecting build commands:

```bash
command -v gcc gfortran mpicc mpif90 mpirun nc-config nf-config
gcc --version
gfortran --version
mpirun --version
mpif90 --showme:command
mpif90 --showme:link
nc-config --all
nf-config --all
module -t list 2>&1 || true
```

Use `scripts/inventory.sh` and preserve its output. If the image provides
multiple MPI or NetCDF installations, deliberately select one coherent stack,
then repeat discovery after loading its module or environment script. Do not
combine wrappers, headers, or libraries from different installations.
Inspect `/opt` first because it is the usual location for Azure HPC image
stacks, but fall back to modules, `PATH`, environment variables, and other
installation prefixes when it is absent or different.

## Storage preflight

Check capacity and write access before downloading or extracting:

```bash
df -h "$ARCHIVE_DIR" "$RUN_PARENT"
test -w "$ARCHIVE_DIR" && test -w "$RUN_PARENT"
```

Budget for the compressed archive, extracted inputs, retained reference output,
new WRF output, logs, and safety margin. The official v4.2 archive alone is
about 14 GiB, so a typical OS/root volume may be too small. Stage directly on a
large writable local filesystem and avoid copying the archive into each run
directory. Recheck free space immediately before launch.

## Build sequence

Use the paths discovered on the current image; do not assume `/mnt`, `/opt`, a
module name, an HPC-X release, or an installation layout.

```bash
git clone --branch v4.4.2 --depth 1 --recurse-submodules \
  https://github.com/wrf-model/WRF.git "$WRF_SRC"
cd "$WRF_SRC"

export PATH="$MPI_ROOT/bin:$PATH"
export NETCDF="$NETCDF_ROOT"
export NETCDF_classic=1
export WRFIO_NCD_LARGE_FILE_SUPPORT=1

printf '34\n1\n' | ./configure | tee configure.log
```

`MPI_ROOT` and `NETCDF_ROOT` above are caller-selected paths discovered for the
current image, not fixed image locations. If the active environment already
provides the correct wrappers and configuration tools, derive the values from
those tools rather than inventing prefixes.

Before compilation, inspect `configure.wrf`:

1. `DM_FC` and `DM_CC` must invoke working MPI wrappers. Some WRF/Open MPI
   combinations emit obsolete wrapper selectors such as `-f90=` or `-cc=`.
   Test the wrappers and remove only unsupported selectors.
2. `LIB_EXTERNAL` must include NetCDF-Fortran and NetCDF-C. Use
   `nf-config --flibs` to discover the correct flags; do not assume
   `$NETCDF/lib`, because distributions may use multiarch directories.
   On Ubuntu/Debian HPC images, the NetCDF Fortran stack often resolves only
   through `$(shell nf-config --flibs)`. If the linker errors with
   `undefined reference to nf_*` in `wrf_io.f`, update `configure.wrf` to add
   that flag set; do not keep a broken binary.
3. Set the intended `FCOPTIM` exactly:

```text
Benchmark:   -O3 -march=znver4 -Ofast -ftree-vectorize -funroll-loops
Conservative: -O3 -march=znver4 -ftree-vectorize -funroll-loops
```

Then build:

```bash
./compile -j <reasonable-build-parallelism> em_real 2>&1 | tee compile.log
```

WRF makefiles internally serialize parts of the build; a large `-j` value does
not imply all cores will be used.

## Validation

Require all of the following:

```bash
test -x main/wrf.exe
test -x main/real.exe
ldd main/wrf.exe | grep -q 'not found' && exit 1 || true
scripts/build-manifest.sh "$WRF_SRC"
```

Also require a successful benchmark run and numerical output comparison.
Compilation success alone does not validate the executable.

After any base-image update, rebuild or revalidate the executable. A previously
built binary is reusable only if its runtime libraries still resolve and its
manifest shows the intended active stack.

For an exact external-report reproduction, build WRF 4.2.2 with its matching
v4.2 benchmark data. Do not describe WRF 4.4.2 plus v4.2 data as an exact
software-stack reproduction.
