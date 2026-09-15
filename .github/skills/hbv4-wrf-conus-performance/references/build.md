# Build WRF

Use `scripts/build-wrf.sh` after the [runbook's checks](../SKILL.md).
It has three steps: **prepare environment, configure, build**. It uses the
selected stack, keeps logs, and stops at an error. There is no installer,
JSON state, automatic cleanup, or resume framework.

## 1. Select the stack

Load the appropriate module or environment script from the current image.
Do not assume a fixed `/opt` prefix or purge the user's modules.

```bash
command -v gcc gfortran mpicc mpif90 mpirun nc-config nf-config csh
mpif90 --showme:command
mpicc --showme:command
mpirun --version
nc-config --all
nf-config --all
```

This recipe supports Linux x86_64, GNU compilers, Open MPI/HPC-X, and WRF's
legacy `configure` interface. The wrappers must select `gcc` and `gfortran`
from PATH. NetCDF-C and Fortran must share a prefix with `include/netcdf.inc`;
multiarch library directories are supported through `nf-config --flibs`.
Paths must not contain whitespace; use ordinary flags, not shell/make expressions.

Prefer the original dependencies: **zlib 1.2.13, HDF5 1.12.2, NetCDF-C 4.7.4,
NetCDF-Fortran 4.5.3**. Locate matching installations first. If unavailable or
unsuitable because of an identified security/support concern, document the
original version, replacement, reason and user approval. Do not downgrade
image-owned packages or rebuild dependencies automatically.

The script checks the requested NetCDF versions. Confirm zlib/HDF5 and the
baseline compiler/MPI versions using the selected stack's package/build records
and linkage. Matching WRF/data alone is not an exact software-stack comparison.

## 2. Prepare WRF 4.2.2 source

Use the absolute `SKILL_DIR` and `WRF_SRC` paths from the runbook. After
download approval, clone only if the directory is absent:

```bash
if [[ ! -e "$WRF_SRC" ]]; then
  git clone --branch v4.2.2 --depth 1 --recurse-submodules \
    https://github.com/wrf-model/WRF.git "$WRF_SRC"
fi
test "$(git -C "$WRF_SRC" rev-parse HEAD)" = \
  fb60d61cc44e2a2e8b8311f0b79185724010d510 ||
  { echo "Expected the WRF v4.2.2 comparison commit" >&2; exit 1; }
git -C "$WRF_SRC" status --short
```

Review source changes. The build script requires an unconfigured tree without
old objects or executables; it will not overwrite an existing build. Keep
validated binaries rather than rebuilding needlessly.

## 3. Build

After approving `-Ofast`'s relaxed floating-point semantics, set the benchmark
flags and run one command:

```bash
export WRF_FCFLAGS="-O3 -march=znver4 -Ofast -ftree-vectorize -funroll-loops"
NPROCS=8 bash "$SKILL_DIR/scripts/build-wrf.sh" "$WRF_SRC"
```

| Setting | Default / purpose |
|---|---|
| `NPROCS` | 8 compile jobs; choose within the allocation, not the MPI rank count |
| `BUILD_TIMEOUT` | 3600 seconds for compilation; not a benchmark timeout |
| `WRF_FCFLAGS` | Plain `-O3` unless explicitly set; use the command above for the benchmark |
| `WRF_NETCDF_C_VERSION` | 4.7.4; change only for a documented approved exception |
| `WRF_NETCDF_FORTRAN_VERSION` | 4.5.3; change only for a documented approved exception |

The script first compiles a small MPI/NetCDF Fortran link probe; it does not
execute it. It discovers the GNU dmpar menu entry, selects basic nesting 1,
sets MPI wrappers and exact optimization flags, then compiles `em_real`.
NetCDF link flags come from `nf-config`, not a guessed library directory.
No packages, source or datasets are downloaded by the build script.

## Result and recovery

The terminal prints the stage and a `WRF_SRC/build-logs.XXXXXX` directory.
Start with `configure.log` or `compile.log` if it fails. Successful builds
have `main/wrf.exe`, `main/real.exe`, linkage reports, `build-manifest.txt`,
output hashes, and before/after configuration copies. Read the linkage reports
to confirm the intended libraries, not just the absence of missing libraries.
Return to **Run** in the runbook; `BUILD PASS` is not scientific validation.

On failure, keep the source, configuration and logs. Identify the cause before
retrying. The script deliberately refuses to reconfigure that tree. An agent
or experienced user can resume the native WRF compile after checking the
unchanged stack/configuration and preserving any old executables and logs;
there is no automated resume guarantee. Use a fresh checkout when changing
the toolchain or flags. Never clean, delete or reinstall speculatively.

If the script is wrong, make the smallest justified fix and validate it before
retrying. Do not change WRF/data versions or bypass checks merely to get a
successful exit.

## Translating a cluster-validation recipe

Do not source infrastructure `constants.sh`: it can run cloud queries and
contains unrelated provisioning and upload settings. `WRF_SRC` here means
the actual WRF checkout, not the validation-script directory. Fixed workspace
paths and module names are discovery hints, not requirements.

Keep WRF **4.2.2** and the **v4.2 CONUS dataset**. Use the approved HBv4
`znver4` target and record the difference from earlier `znver2` builds.
Historical WRF 4.4.2 results stay in [results.md](results.md), not relabeled.
Four nodes with 144 ranks each is a separate future MPI/IB workflow, not this
single-node 176-rank baseline.
