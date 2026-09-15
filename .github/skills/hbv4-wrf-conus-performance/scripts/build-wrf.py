#!/usr/bin/env python3
"""Build an existing WRF GNU dmpar checkout using the selected image stack."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile


class BuildError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise BuildError(message)


def positive_integer(value):
    if not value.isdecimal() or int(value) < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return int(value)


def make_value(value):
    require(
        bool(re.fullmatch(r"[A-Za-z0-9_./,:=+@%-]+", value)),
        f"Unsupported whitespace or make/shell syntax in value: {value!r}",
    )
    return value


def replace_setting(text, key, value):
    text, count = re.subn(
        rf"^{key}\s*=.*$", lambda _: f"{key} = {value}", text, flags=re.MULTILINE
    )
    require(count == 1, f"Expected one {key} assignment; found {count}. Unsupported configure.wrf.")
    return text


def gnu_dmpar_choice(menu):
    choices = []
    for line in menu.splitlines():
        if re.search(r"GNU \(gfortran/gcc\)\s*$", line):
            match = re.search(r"(\d+)\.\s+\(dmpar\)", line)
            if match:
                choices.append(match[1])
    require(len(choices) == 1, "Could not identify one GNU (gfortran/gcc) dmpar menu entry.")
    return choices[0]


class Builder:
    def __init__(self, args):
        self.args = args
        self.source = Path(args.source).resolve()
        require(self.source.is_dir(), f"Source directory not found: {self.source}")
        make_value(str(self.source))
        self.lock = (self.source / ".atlas-build.lock").open("a")
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise BuildError("Another Atlas build is using this source directory.") from error
        self.logs = Path(tempfile.mkdtemp(prefix="atlas-build-", dir=self.source))
        self.env = os.environ.copy()
        self.stage = "preflight"

    def command(self, command, log, *, input=None, timeout=120):
        path = self.logs / log
        with path.open("a") as output:
            output.write(f"$ {shlex.join(map(str, command))}\n")
            output.flush()
            try:
                process = subprocess.Popen(
                    command, cwd=self.source, env=self.env, text=True,
                    stdin=subprocess.PIPE if input is not None else subprocess.DEVNULL,
                    stdout=output, stderr=subprocess.STDOUT, start_new_session=True,
                )
                process.communicate(input=input, timeout=timeout)
            except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
                # Descendants may outlive the configure/compile parent.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                raise BuildError(f"Command timed out or was interrupted; inspect {path}") from error
        require(process.returncode == 0, f"Command exited {process.returncode}; inspect {path}")
        return path.read_text()

    def query(self, *command):
        path = self.logs / "preflight.log"
        with path.open("a") as output:
            output.write(f"$ {shlex.join(command)}\n")
            output.flush()
            result = subprocess.run(
                command, cwd=self.source, env=self.env, text=True, stdout=subprocess.PIPE,
                stderr=output, timeout=30, check=False,
            )
            output.write(result.stdout + "\n")
        require(result.returncode == 0, f"Tool query failed; inspect {path}")
        return result.stdout.strip()

    def preflight(self):
        require(sys.platform == "linux" and os.uname().machine == "x86_64",
                "This helper supports the Linux x86_64 GNU dmpar configure interface.")
        for name in ("configure", "compile", "arch/Config.pl", "arch/configure.defaults"):
            require((self.source / name).is_file(), f"Missing WRF source file: {name}")
        for name in ("configure", "compile"):
            require(os.access(self.source / name, os.X_OK), f"WRF {name} is not executable.")
        names = ("gcc", "gfortran", "mpicc", "mpif90", "mpirun", "nc-config",
                 "nf-config", "make", "m4", "perl", "csh", "ldd", "git", "bash")
        self.tools = {}
        for name in names:
            path = shutil.which(name)
            require(path is not None, f"Missing tool: {name}. Select/install a coherent stack first.")
            self.tools[name] = make_value(os.path.abspath(path))
        for wrapper, compiler in (("mpicc", "gcc"), ("mpif90", "gfortran")):
            command = shlex.split(self.query(self.tools[wrapper], "--showme:command"))
            require(len(command) == 1 and shutil.which(command[0]) is not None,
                    f"{wrapper} must select a single GNU compiler, not a wrapper chain.")
            require(Path(shutil.which(command[0])).resolve() == Path(self.tools[compiler]).resolve(),
                    f"{wrapper} does not select the active {compiler}. Fix PATH/module selection.")
        mpi_bins = {Path(self.tools[name]).resolve().parent
                    for name in ("mpicc", "mpif90", "mpirun")}
        require(len(mpi_bins) == 1, "MPI wrappers and mpirun resolve to different installations.")
        versions = {name: self.query(self.tools[name], "--version")
                    for name in ("gcc", "gfortran", "mpirun", "nc-config", "nf-config")}
        require("Open MPI" in versions["mpirun"], "Select Open MPI or an HPC-X Open MPI stack.")
        required_versions = {
            "nc-config": self.args.require_netcdf_c,
            "nf-config": self.args.require_netcdf_fortran,
        }
        for name, expected in required_versions.items():
            if expected is not None:
                observed = re.search(r"\b\d+\.\d+(?:\.\d+)*\b", versions[name])
                require(observed is not None and observed.group() == expected,
                        f"{name} requires {expected}, found {versions[name]!r}. "
                        "Locate the baseline stack or document and approve a dependency exception.")
        nc_prefix = self.query(self.tools["nc-config"], "--prefix")
        nf_prefix = self.query(self.tools["nf-config"], "--prefix")
        require(nc_prefix == nf_prefix,
                "This helper requires NetCDF-C and Fortran under one prefix. Select a matching stack.")
        make_value(nc_prefix)
        require((Path(nc_prefix) / "include/netcdf.inc").is_file(),
                "netcdf.inc is missing from the selected NetCDF prefix/include.")
        nf_flags = shlex.split(self.query(self.tools["nf-config"], "--fflags"))
        nf_libs = shlex.split(self.query(self.tools["nf-config"], "--flibs"))
        nc_flags = shlex.split(self.query(self.tools["nc-config"], "--cflags"))
        nc_libs = shlex.split(self.query(self.tools["nc-config"], "--libs"))
        self.args.fcflags = " ".join(shlex.split(self.args.fcflags))
        for value in nf_flags + nf_libs + nc_flags + nc_libs + shlex.split(self.args.fcflags):
            make_value(value)
        require(self.args.fcflags.strip(), "--fcflags must not be empty.")
        require("-lnetcdff" in nf_libs and "-lnetcdf" in nf_libs,
                "nf-config --flibs must include both NetCDF-Fortran and NetCDF-C.")
        require("NETCDF_LDFLAGS" in (self.source / "arch/Config.pl").read_text(),
                "This WRF configuration interface lacks NETCDF_LDFLAGS support.")
        for name in ("PNETCDF", "NETCDFPAR", "WRF_CHEM", "WRF_DA_CORE", "WRF_HYDRO",
                     "WRFPLUS", "WRFPLUS_CORE", "WRF_NMM_CORE", "WRF_CMAQ",
                     "WRF_MARS", "WRF_TITAN", "WRF_VENUS", "WRF_KPP", "WRF_DFI_RADAR"):
            require(self.env.get(name, "") in ("", "0"),
                    f"{name} enables an unsupported build variant; use a separate explicit environment.")
        for name in ("WRF_CTSM_MKFILE", "ESMFLIB", "ESMFINC"):
            require(not self.env.get(name), f"{name} enables an unsupported coupled-model build.")
        if self.env.get("NETCDF"):
            require(Path(self.env["NETCDF"]).resolve() == Path(nc_prefix).resolve(),
                    "NETCDF disagrees with nc-config. Select one stack before building.")
        self.env.update(NETCDF=nc_prefix, NETCDF_classic="1",
                        NETCDF_LDFLAGS=" ".join(nf_libs), WRFIO_NCD_LARGE_FILE_SUPPORT="1")
        self.context = {
            "source": str(self.source), "fcflags": self.args.fcflags, "tools": self.tools,
            "versions": versions, "netcdf": nc_prefix, "nf_flags": nf_flags,
            "required_versions": required_versions,
            "nf_libs": nf_libs, "nc_flags": nc_flags, "nc_libs": nc_libs,
            "source_commit": self.query(self.tools["git"], "-C", str(self.source), "rev-parse", "HEAD")
            if (self.source / ".git").exists() else None,
            "environment": {key: self.env.get(key, "") for key in
                            ("PATH", "LD_LIBRARY_PATH", "LIBRARY_PATH", "CPATH",
                             "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "OMPI_CC", "OMPI_FC",
                             "CC", "CXX", "FC", "F77", "F90", "CFLAGS", "CXXFLAGS",
                             "FFLAGS", "FCFLAGS", "CPPFLAGS", "LDFLAGS", "MAKEFLAGS")},
        }
        (self.logs / "context.json").write_text(json.dumps(self.context, indent=2) + "\n")
        c_probe = self.logs / "probe.c"
        c_probe.write_text(
            "#include <mpi.h>\n#include <netcdf.h>\n"
            "int main(void) { int flag; MPI_Initialized(&flag); return nc_inq_libvers() == 0; }\n"
        )
        f_probe = self.logs / "probe.f90"
        f_probe.write_text(
            "program probe\nuse mpi\nuse netcdf\nimplicit none\n"
            "logical flag\ninteger ierr\ncall MPI_Initialized(flag, ierr)\n"
            "print *, nf90_inq_libvers()\nend program\n"
        )
        for compiler, source, flags, libs in (
            ("mpicc", c_probe, nc_flags, nc_libs),
            ("mpif90", f_probe, shlex.split(self.args.fcflags) + nf_flags, nf_libs),
        ):
            exe = source.with_suffix(".exe")
            self.command([self.tools[compiler], *flags, str(source), *libs, "-o", str(exe)],
                         "preflight.log")
            self.check_libraries(exe, "preflight.log")
        print(f"CHECK PASS: compiler/MPI/NetCDF compile and link probes; logs: {self.logs}", flush=True)

    def check_libraries(self, executable, log):
        text = self.command([self.tools["ldd"], str(executable)], log)
        require("not found" not in text, f"Unresolved runtime libraries; inspect {self.logs / log}")

    def configure(self):
        self.stage = "configure"
        if self.args.resume:
            previous = Path(self.args.resume).resolve()
            require(previous.parent == self.source, "--resume must name a prior atlas-build directory here.")
            for name in ("context.json", "configure.wrf"):
                require((previous / name).is_file(), f"Resume evidence is missing: {previous / name}")
            require(json.loads((previous / "context.json").read_text()) == self.context,
                    "Toolchain/environment/flags changed. Do not reuse old objects; use a fresh checkout.")
            require((self.source / "configure.wrf").read_bytes() == (previous / "configure.wrf").read_bytes(),
                    "configure.wrf changed. Use a fresh checkout for a configuration change.")
        else:
            require(not (self.source / "configure.wrf").exists(),
                    "Source is already configured. Reuse its executable, use --resume, or choose a fresh checkout.")
            require(not any((self.source / "main" / name).exists()
                            or (self.source / "main" / name).is_symlink()
                            for name in ("wrf.exe", "real.exe")),
                    "Existing executables found. Reuse them or choose a fresh checkout.")
            require(not any(self.source.rglob("*.o")),
                    "Existing object files found. Use --resume with matching evidence or a fresh checkout.")
            menu = self.command(
                [self.tools["perl"], "arch/Config.pl", "-os=Linux", "-mach=x86_64"],
                "menu.log", input="-1\n", timeout=30,
            )
            choice = gnu_dmpar_choice(menu)
            print(f"CONFIGURE: GNU dmpar menu entry {choice}; basic nesting 1", flush=True)
            self.command(["./configure", "-os", "Linux", "-mach", "x86_64"],
                         "configure.log", input=f"{choice}\n1\n")
            config = self.source / "configure.wrf"
            require(config.is_file(), "configure did not create configure.wrf.")
            shutil.copy2(config, self.logs / "configure.original.wrf")
            text = config.read_text()
            for key, value in (
                ("SFC", self.tools["gfortran"]), ("SCC", self.tools["gcc"]),
                ("CCOMP", self.tools["gcc"]), ("DM_FC", self.tools["mpif90"]),
                ("DM_CC", self.tools["mpicc"]), ("FCOPTIM", self.args.fcflags),
            ):
                text = replace_setting(text, key, value)
            require(all(value in text for value in self.context["nf_libs"]),
                    "Generated configuration did not retain nf-config link flags.")
            config.write_text(text)
        shutil.copy2(self.source / "configure.wrf", self.logs / "configure.wrf")

    def build(self):
        self.stage = "compile"
        for name in ("wrf.exe", "real.exe"):
            path = self.source / "main" / name
            if path.exists() or path.is_symlink():
                require(self.args.resume, f"Existing {path}; refusing to replace a previous executable.")
                require(not path.is_dir(), f"Unexpected executable directory: {path}")
                previous = self.logs / f"previous-{name}"
                if path.is_symlink():
                    shutil.copy2(path.resolve(strict=True), previous)
                    path.unlink()
                else:
                    path.rename(previous)
        print(f"BUILD: em_real, {self.args.jobs} jobs; log: {self.logs / 'compile.log'}", flush=True)
        self.command(["./compile", "-j", str(self.args.jobs), "em_real"],
                     "compile.log", timeout=self.args.timeout)
        self.stage = "validate"
        for name in ("wrf.exe", "real.exe"):
            path = self.source / "main" / name
            require(path.is_file() and os.access(path, os.X_OK),
                    f"Build did not produce executable {path}; inspect compile.log.")
            self.check_libraries(path, "linked-libraries.txt")
        manifest = Path(__file__).with_name("build-manifest.sh")
        self.command([self.tools["bash"], str(manifest), str(self.source)], "build-manifest.txt")
        for name in ("wrf.exe", "real.exe"):
            path = self.source / "main" / name
            with path.open("rb") as stream:
                digest = hashlib.sha256()
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            with (self.logs / "outputs.sha256").open("a") as output:
                output.write(f"{digest.hexdigest()}  {path}\n")
        print(f"BUILD PASS: {self.source / 'main/wrf.exe'}\n"
              f"Evidence: {self.logs}\nNo benchmark or scientific validation was run.", flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", help="existing WRF source directory; no cloning or downloads")
    parser.add_argument("--jobs", type=positive_integer, default=8, help="build parallelism (default: 8)")
    parser.add_argument("--fcflags", default="-O3", help="Fortran flags (default: -O3; no implicit -Ofast)")
    parser.add_argument("--require-netcdf-c", metavar="VERSION", help="require this NetCDF-C version")
    parser.add_argument("--require-netcdf-fortran", metavar="VERSION", help="require this NetCDF-Fortran version")
    parser.add_argument("--check", action="store_true", help="run small compile/link probes only")
    parser.add_argument("--resume", metavar="LOG_DIRECTORY", help="retry compilation with unchanged build context")
    parser.add_argument("--timeout", type=positive_integer, default=3600, help="compile deadline in seconds (default: 3600)")
    args = parser.parse_args(argv)
    builder = None
    try:
        builder = Builder(args)
        builder.preflight()
        if not args.check:
            builder.configure()
            builder.build()
        return 0
    except (BuildError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        stage = builder.stage if builder else "setup"
        location = f"\nEvidence preserved: {builder.logs}" if builder else ""
        print(f"BUILD FAILED [{stage}]: {error}{location}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
