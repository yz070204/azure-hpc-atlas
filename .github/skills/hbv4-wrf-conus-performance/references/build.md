# Reproducible WRF build

This is the **Build** stage of [the runbook](../SKILL.md). Complete its
Check stage first and retain the absolute `SKILL_DIR`, `WORK_ROOT`, and
`WRF_SRC` variables. Prefer `scripts/build-wrf.py` for routine steps; humans
and agents use the same commands. Do not compare binaries without build evidence.

## Single-node comparison target

```text
Source: https://github.com/wrf-model/WRF.git
Tag: v4.2.2
Commit: fb60d61cc44e2a2e8b8311f0b79185724010d510
Dataset: v422/v42_bench_conus2.5km.tar.gz (unchanged checksum in results.md)
Preferred dependencies: zlib 1.2.13, HDF5 1.12.2,
                        NetCDF-C 4.7.4, NetCDF-Fortran 4.5.3
Compiler/MPI: match the selected prior run where known; discover actual paths
Configure: GNU dmpar (discover menu entry), basic nesting option 1
FCOPTIM: -O3 -march=znver4 -Ofast -ftree-vectorize -funroll-loops
```

This preserves the supplied validation recipe's WRF/data versions and
`-Ofast`, using the approved HBv4 `znver4` target instead of the older
`znver2`. Record this ISA-target difference. The explicit `FCOPTIM` also retains the GNU template's
vectorization/unrolling flags instead of accumulating duplicate optimization
options. Compare the complete old `configure.wrf` and build manifest before
claiming an exact build match. There is no newly measured WRF 4.2.2 baseline
from this helper yet; older WRF 4.4.2 measurements remain in
[results.md](results.md), not relabeled as 4.2.2.

Prefer matching dependency versions, but not fixed installation paths. Search
the selected image/modules and approved existing artifacts first. If a baseline
dependency cannot be located or obtained from an approved source, or an
identified advisory/support policy rules it out, record the original version,
replacement, reason and user approval. Matching WRF/data then permits a
controlled comparison with a disclosed dependency difference, not an exact
software-stack reproduction. Do not install an affected version just to match
an old result, or replace system libraries behind the image's package manager.

The source commit and flags are intentionally required by the runner. The
helper uses GNU dmpar and Open MPI/HPC-X; another compiler family or WRF build
interface is outside this recipe, not a reason for guessed substitutions.

## Discover the current image stack

Select a baseline-matching compiler/MPI/NetCDF stack where available.
Load its documented module or environment script if needed, then inspect:

```bash
command -v gcc gfortran mpicc mpif90 mpirun nc-config nf-config
gcc --version
gfortran --version
mpirun --version
mpif90 --showme:command
mpif90 --showme:link
nc-config --all
nf-config --all
```

The helper uses active commands, not a hard-coded module, workspace, or
installation prefix. `inventory.sh` can find candidate stacks under `/opt`
and other local paths, but does not select one. The helper never purges
modules, calls sudo, installs packages, or rebuilds zlib/HDF5/NetCDF.
Reuse matching libraries from the image where available. A different image
version is not itself permission to change the comparison. Missing or
incompatible dependencies require a separate approved setup action or an
explicit dependency exception. The helper gates requested NetCDF versions;
confirm zlib/HDF5 versions separately using the selected stack's package/build
records and linkage. A default `pkg-config` result for an unrelated installation
does not establish which libraries WRF will use.

Supported scope: Linux x86_64, GNU compilers, one Open MPI/HPC-X installation,
and the legacy WRF `configure`/`arch/Config.pl` GNU dmpar interface. NetCDF-C
and NetCDF-Fortran must report the same prefix, with `include/netcdf.inc`;
library paths may be multiarch and are taken from `nf-config --flibs`.
Individual path/flag tokens containing whitespace or make/shell metacharacters
are not supported; spaces between flags are expected. New WRF build systems,
split NetCDF prefixes, and compiler wrapper
chains stop with an explicit limitation rather than speculative patches.

## Prepare the source

The helper takes an existing source tree. After download approval, clone only
if the selected directory is absent; do not overwrite or switch an existing
checkout. This pinned source belongs to the benchmark recipe, not to the
generic build helper:

```bash
if [[ ! -e "$WRF_SRC" ]]; then
  git clone --branch v4.2.2 --depth 1 --recurse-submodules \
    https://github.com/wrf-model/WRF.git "$WRF_SRC"
fi
test "$(git -C "$WRF_SRC" rev-parse HEAD)" = \
  fb60d61cc44e2a2e8b8311f0b79185724010d510 ||
  { echo "Source does not match the WRF v4.2.2 comparison commit" >&2; exit 1; }
git -C "$WRF_SRC" status --short
```

Review any source changes before continuing; a matching commit alone does not
prove an unmodified source tree. Start a new build with an unconfigured tree
without old object files or executables. Existing builds are not cleaned or
reconfigured automatically: reuse a validated executable, or use the resume
procedure below for an attempt made by this helper.

## Check, then build

After agreeing to the benchmark's relaxed floating-point semantics:

```bash
export WRF_FCFLAGS="-O3 -march=znver4 -Ofast -ftree-vectorize -funroll-loops"
export WRF_NETCDF_C_VERSION=4.7.4
export WRF_NETCDF_FORTRAN_VERSION=4.5.3
python3 "$SKILL_DIR/scripts/build-wrf.py" "$WRF_SRC" \
  --check --fcflags="$WRF_FCFLAGS" \
  --require-netcdf-c="$WRF_NETCDF_C_VERSION" \
  --require-netcdf-fortran="$WRF_NETCDF_FORTRAN_VERSION"
```

Change these expected NetCDF versions only after documenting an approved
exception. Do not drop the version arguments to bypass a mismatch.

`CHECK PASS` means the selected wrappers can compile/link tiny C and Fortran
MPI/NetCDF probes and their runtime libraries resolve. The check writes logs
and probe files under the source directory; it does not configure or compile
WRF, run MPI jobs, or execute the probes. Flag support is tested, not inferred
from a guessed minimum GCC version. Do not silently change the target ISA or
scientific flags to make a compiler probe pass.

Recheck disk space and node activity as described in the runbook, then choose
build parallelism within the approved allocation. Eight jobs and a one-hour
deadline are conservative helper defaults, not performance recommendations:

```bash
python3 "$SKILL_DIR/scripts/build-wrf.py" "$WRF_SRC" \
  --jobs 8 --timeout 3600 --fcflags="$WRF_FCFLAGS" \
  --require-netcdf-c="$WRF_NETCDF_C_VERSION" \
  --require-netcdf-fortran="$WRF_NETCDF_FORTRAN_VERSION"
```

The helper repeats preflight, selects the GNU dmpar entry by its label rather
than a fixed menu number, and requests basic nesting 1. It sets the selected
GNU compilers/MPI wrappers and exact Fortran flags in `configure.wrf`, avoiding
obsolete `-f90=`/`-cc=` wrapper selectors. It passes the discovered
NetCDF-Fortran link flags through WRF's `NETCDF_LDFLAGS` interface. It preserves
the original generated configuration and stops if expected settings or that
interface are missing.

Build stdout/stderr go to logs instead of flooding the terminal. The helper
reports the stage and evidence directory, enforces the compile deadline, and
stops its own command group on timeout/interruption. It does not clean source,
format storage, fetch dependencies, download benchmark data, or launch WRF.

## Read the checkpoint

Each invocation prints its own `WRF_SRC/atlas-build-...` directory:

| Evidence | Purpose |
|---|---|
| `preflight.log`, `context.json` | Selected commands, versions, flags, relevant environment and link probes |
| `menu.log`, `configure.log` | Detected configure entry and configuration output (new builds) |
| `configure.original.wrf`, `configure.wrf` | Before/after configuration (original exists for new builds) |
| `compile.log` | Complete compile output and exact command |
| `linked-libraries.txt`, `build-manifest.txt`, `outputs.sha256` | Runtime linkage, provenance and executable hashes |

**Build checkpoint:** `BUILD PASS`, fresh `main/wrf.exe` and `main/real.exe`,
resolved libraries, and saved evidence. Read the linkage report to confirm
the intended library identities; symbol resolution alone is not proof of the
intended stack. Preserve source edits alongside build evidence. A snapshot of
today's compiler/configuration cannot establish an older binary's provenance.
Return to **Run** in [the runbook](../SKILL.md); scientific validation is later.

## Failure and bounded recovery

`BUILD FAILED [stage]` includes the reason and evidence location. Read that
stage's log first. Fix only an evidenced cause; do not bypass the checker or
change the benchmark's source/flags to obtain success. Dependency installation
or global changes still require approval. If a script fix is needed, preserve
local changes and validate the fix before retrying; stop if the same failure
recurs without new evidence.

For a failed compile with unchanged source revision, toolchain, environment,
flags and configuration, reuse objects instead of configuring again:

```bash
read -r -p "Previous atlas-build log directory (absolute path): " BUILD_LOG_DIR
python3 "$SKILL_DIR/scripts/build-wrf.py" "$WRF_SRC" \
  --resume "$BUILD_LOG_DIR" --jobs 8 --timeout 3600 --fcflags="$WRF_FCFLAGS" \
  --require-netcdf-c="$WRF_NETCDF_C_VERSION" \
  --require-netcdf-fortran="$WRF_NETCDF_FORTRAN_VERSION"
```

Resume requires the previous `context.json` and configured `configure.wrf`
snapshot; it is not available after an incomplete configuration. It rechecks
the stack and configuration, preserves any old main executables in the new
log directory, and requires new outputs. Changed flags, stack, environment,
or source revision require a separate clean checkout rather than mixing old
objects. No automatic destructive `clean` is performed.

For completed builds, return to the runbook instead of using `--resume`
unnecessarily. After an image update, revalidate runtime libraries and recorded
provenance before deciding whether a rebuild is needed.

## Separate experiments, not fallback fixes

### Translating a cluster-validation recipe

An older cluster-validation build may use a shared `constants.sh`. Do not
source or copy that file into this workflow: it can execute metadata/cloud
queries and includes deployment-specific identities, uploads, provisioning,
and unrelated benchmarks. Use only the relevant build/run choices:

| Legacy setting | Treatment in this standalone workflow |
|---|---|
| `WRF_VERSION=4.2.2` | Keep as the standalone default, pinned to its verified source commit; do not substitute 4.4.2 or the latest release |
| `WRF_DATA_URL` pointing to `v422/v42_bench_conus2.5km.tar.gz` | Keep this dataset for the default; its version is independent of the WRF executable version |
| zlib 1.2.13, HDF5 1.12.2, NetCDF-C 4.7.4, NetCDF-Fortran 4.5.3 | Preferred comparison versions. Search for them first; document unavailable/security/support exceptions before using replacements |
| `MPI_HPCX_MODULE=mpi/hpcx` | A selection hint only if that module exists; inspect the active wrappers and launcher after loading it |
| `NPROCS=96` | Build parallelism only. Choose `--jobs` within the allocation; do not equate it with MPI ranks |
| Four nodes, 144 ranks per node on HBv4 | A different multi-node experiment. The local runner uses one node, 176 ranks and a 16x11 grid; neither layout is universally optimal |
| One thread per process | Keep for the default pure-MPI run |
| `-march=znver2 -Ofast` in the old build | Use the approved HBv4 `znver4` target and record the difference; retain `-Ofast` consistently with relaxed-floating-point approval |
| `WRF_TIMEOUT_SECONDS=1800` | A job execution budget, not a compile timeout or performance threshold. The standalone runner does not read this constant; the build helper's `--timeout` bounds compilation only |
| Fixed workspace, source, input, output and HPC-X paths | Replace with explicit discovered paths. Do not select the first matching HPC-X directory when several stacks exist |

In particular, the old `WRF_SOURCE_DIR` can name the validation scripts
directory, not the unpacked WRF code. Our `WRF_SRC` must contain WRF's
`configure`, `compile`, and `arch/Config.pl`; for the default recipe it must
also be the pinned Git checkout. Do not map these variables by name alone.

For an image-owned stack, follow the image's supported package/update policy.
If dependencies must instead be built privately, treat that as a separate,
approved, versioned recipe with verified archives and a full rebuild.
Changing WRF, MPI, NetCDF, compiler or scientific flags creates a new measured
configuration: preserve old results and rerun performance and correctness
comparisons rather than relabeling historical timings.

### Separate tuning and historical comparisons

A conservative scientific build can pass
`--fcflags="-O3 -march=znver4 -ftree-vectorize -funroll-loops"` without `-Ofast`
(the helper's default is plain `-O3`), but the current runner rejects those
flags. WRF 4.4.2 remains a separate historical/tuning configuration even when
using the same `znver4 -Ofast` flags. Keep its measurements intact. Exact external-report
reproduction additionally needs that report's compiler, MPI, dependency,
placement and measurement conditions; the same WRF and dataset versions alone
are insufficient.
