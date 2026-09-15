import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/build-wrf.py"
SPEC = importlib.util.spec_from_file_location("build_wrf", SCRIPT)
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)


TOOLS = r"""#!/usr/bin/env python3
import os
from pathlib import Path
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
mode = os.environ.get("FAKE_MODE", "")
prefix = os.environ["FAKE_NETCDF"]
if "--showme:command" in args:
    print("gcc" if name == "mpicc" else ("wrong-compiler" if mode == "wrong-compiler" else "gfortran"))
elif "--version" in args:
    print("Open MPI 5.0.10" if name == "mpirun" else name + " 1.0")
elif "--prefix" in args:
    print(prefix + "-other" if name == "nf-config" and mode == "split-netcdf" else prefix)
elif "--fflags" in args or "--cflags" in args:
    print("-I" + prefix + "/include")
elif "--flibs" in args:
    print("-L" + prefix + "/lib -lnetcdff -lnetcdf")
elif "--libs" in args:
    print("-L" + prefix + "/lib -lnetcdf")
elif name in ("mpicc", "mpif90"):
    if "-bad-flag" in args:
        print("unsupported compiler flag", file=sys.stderr)
        sys.exit(2)
    Path(args[args.index("-o") + 1]).write_text("probe")
elif name == "ldd":
    print("libnetcdff.so => " + ("not found" if mode == "missing-runtime" else prefix + "/lib/libnetcdff.so"))
elif name == "perl":
    print(" 40. (serial) 41. (smpar) 42. (dmpar) 43. (dm+sm) GNU (gfortran/gcc)")
elif name == "git":
    if "--is-inside-work-tree" in args:
        sys.exit(1)
    if "rev-parse" in args:
        print(os.environ.get("FAKE_GIT_COMMIT", ""))
"""

CONFIGURE = r"""#!/usr/bin/env python3
import os
from pathlib import Path
import sys

answers = sys.stdin.read()
if answers != "42\n1\n":
    sys.exit(9)
mode = os.environ.get("FAKE_MODE", "")
if mode == "configure-fail":
    sys.exit(7)
settings = [
    "DESCRIPTION = GNU (gfortran/gcc)",
    "SFC = gfortran", "SCC = gcc", "CCOMP = gcc",
    "DM_FC = mpif90 -f90=$(SFC)", "DM_CC = mpicc -cc=$(SCC)",
    "FCOPTIM = -O2",
    "LIB_EXTERNAL = $(WRF_SRC_ROOT_DIR)/external/io_netcdf/libwrfio_nf.a " + os.environ["NETCDF_LDFLAGS"],
]
if mode == "unknown-config":
    settings.remove("FCOPTIM = -O2")
Path("configure.wrf").write_text("\n".join(settings) + "\n")
"""

COMPILE = r"""#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys
import time

Path("compile-called").write_text(" ".join(sys.argv[1:]))
mode = os.environ.get("FAKE_MODE", "")
if mode == "compile-timeout":
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
    Path("child.pid").write_text(str(child.pid))
    time.sleep(20)
if mode == "compile-fail":
    Path("partial.o").write_text("partial build")
    sys.exit(8)
if mode == "silent-fail":
    sys.exit(0)
Path("main").mkdir(exist_ok=True)
for name in ("wrf.exe", "real.exe"):
    path = Path("main") / name
    path.write_text("#!/bin/sh\nexit 0\n")
    path.chmod(0o755)
"""


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wrf-build-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        (self.source / "arch").mkdir(parents=True)
        (self.source / "arch/Config.pl").write_text("# NETCDF_LDFLAGS\n")
        (self.source / "arch/configure.defaults").write_text("test configuration")
        self.write_executable(self.source / "configure", CONFIGURE)
        self.write_executable(self.source / "compile", COMPILE)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for name in ("gcc", "gfortran", "mpicc", "mpif90", "mpirun", "nc-config",
                     "nf-config", "make", "m4", "perl", "csh", "ldd", "git"):
            self.write_executable(bin_dir / name, TOOLS)
        prefix = self.root / "netcdf"
        (prefix / "include").mkdir(parents=True)
        (prefix / "include/netcdf.inc").write_text("test include")
        self.env = {
            "PATH": f"{bin_dir}:{os.path.dirname(sys.executable)}:/usr/bin:/bin",
            "HOME": str(self.root),
            "FAKE_NETCDF": str(prefix),
            "LC_ALL": "C",
        }

    @staticmethod
    def write_executable(path, text):
        path.write_text(textwrap.dedent(text))
        path.chmod(0o755)

    def invoke(self, *args, mode="", success=True):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(self.source), *args],
            env={**self.env, "FAKE_MODE": mode}, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
        )
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def latest_logs(self):
        return max(self.source.glob("atlas-build-*"), key=lambda path: path.stat().st_mtime_ns)

    def test_check_does_not_configure_or_build(self):
        self.invoke("--check")
        self.assertFalse((self.source / "configure.wrf").exists())
        self.assertFalse((self.source / "compile-called").exists())
        self.assertTrue((self.latest_logs() / "preflight.log").exists())

    def test_full_build_and_provenance(self):
        self.invoke("--jobs", "3", "--fcflags=-O3 -march=znver4 -Ofast")
        text = (self.source / "configure.wrf").read_text()
        self.assertIn("FCOPTIM = -O3 -march=znver4 -Ofast\n", text)
        self.assertNotIn("-f90=", text)
        self.assertNotIn("-cc=", text)
        self.assertEqual((self.source / "compile-called").read_text(), "-j 3 em_real")
        logs = self.latest_logs()
        for name in ("context.json", "configure.original.wrf", "configure.wrf",
                     "compile.log", "build-manifest.txt", "outputs.sha256"):
            self.assertTrue((logs / name).is_file(), name)
        self.assertEqual(len((logs / "outputs.sha256").read_text().splitlines()), 2)
        self.assertEqual(json.loads((logs / "context.json").read_text())["fcflags"],
                         "-O3 -march=znver4 -Ofast")

    def test_preflight_failure_cases(self):
        for mode in ("wrong-compiler", "split-netcdf", "missing-runtime"):
            with self.subTest(mode=mode):
                result = self.invoke("--check", mode=mode, success=False)
                self.assertIn("BUILD FAILED [preflight]", result.stderr)
                self.assertFalse((self.source / "compile-called").exists())
        self.invoke("--check", "--fcflags=-bad-flag", success=False)
        (self.root / "bin/mpif90").unlink()
        result = self.invoke("--check", success=False)
        self.assertIn("Missing tool: mpif90", result.stderr)

    def test_requested_dependency_versions_are_enforced(self):
        result = self.invoke("--check", "--require-netcdf-c", "4.7.4", success=False)
        self.assertIn("nc-config requires 4.7.4", result.stderr)
        result = self.invoke("--check", "--require-netcdf-fortran", "4.5.3", success=False)
        self.assertIn("nf-config requires 4.5.3", result.stderr)
        self.invoke("--check", "--require-netcdf-c", "1.0", "--require-netcdf-fortran", "1.0")
        context = json.loads((self.latest_logs() / "context.json").read_text())
        self.assertEqual(context["required_versions"], {"nc-config": "1.0", "nf-config": "1.0"})
        self.assertFalse((self.source / "compile-called").exists())

    def test_configure_failure_stops_before_compile(self):
        result = self.invoke(mode="configure-fail", success=False)
        self.assertIn("BUILD FAILED [configure]", result.stderr)
        self.assertFalse((self.source / "compile-called").exists())
        self.assertTrue((self.latest_logs() / "configure.log").exists())

    def test_unrecognized_config_is_not_partially_patched(self):
        self.invoke(mode="unknown-config", success=False)
        self.assertIn("DM_FC = mpif90 -f90=$(SFC)", (self.source / "configure.wrf").read_text())
        self.assertFalse((self.source / "compile-called").exists())

    def test_existing_config_and_outputs_are_preserved(self):
        self.invoke()
        original = (self.source / "configure.wrf").read_bytes()
        result = self.invoke(success=False)
        self.assertIn("already configured", result.stderr)
        self.assertEqual((self.source / "configure.wrf").read_bytes(), original)

    def test_resume_failed_build(self):
        self.invoke(mode="compile-fail", success=False)
        previous = self.latest_logs()
        self.invoke("--resume", str(previous), "--jobs", "2")
        self.assertTrue((self.source / "main/wrf.exe").is_file())
        self.assertEqual((self.source / "compile-called").read_text(), "-j 2 em_real")

    def test_resume_rejects_changed_flags_and_config(self):
        self.invoke(mode="compile-fail", success=False)
        previous = self.latest_logs()
        result = self.invoke("--resume", str(previous), "--fcflags=-O2", success=False)
        self.assertIn("Toolchain/environment/flags changed", result.stderr)
        with (self.source / "configure.wrf").open("a") as file:
            file.write("# edited\n")
        result = self.invoke("--resume", str(previous), success=False)
        self.assertIn("configure.wrf changed", result.stderr)

    def test_stale_executables_cannot_hide_silent_compile_failure(self):
        self.invoke()
        previous = self.latest_logs()
        result = self.invoke("--resume", str(previous), mode="silent-fail", success=False)
        self.assertIn("did not produce executable", result.stderr)
        self.assertTrue((self.latest_logs() / "previous-wrf.exe").is_file())
        self.assertFalse((self.source / "main/wrf.exe").exists())

    def test_compile_deadline(self):
        result = self.invoke("--timeout", "1", mode="compile-timeout", success=False)
        self.assertIn("timed out", result.stderr)
        self.assertTrue((self.latest_logs() / "compile.log").exists())
        pid = int((self.source / "child.pid").read_text())
        status = Path(f"/proc/{pid}/stat")
        if status.exists():
            self.assertEqual(status.read_text().split()[2], "Z", "Child is still running")

    def test_resume_preserves_symlinked_output_contents(self):
        self.invoke()
        previous = self.latest_logs()
        executable = self.source / "main/wrf.exe"
        target = self.source / "original-wrf.exe"
        executable.rename(target)
        executable.symlink_to("../original-wrf.exe")
        self.invoke("--resume", str(previous), mode="silent-fail", success=False)
        saved = self.latest_logs() / "previous-wrf.exe"
        self.assertFalse(saved.is_symlink())
        self.assertEqual(saved.read_bytes(), target.read_bytes())

    def test_bad_argument_fails_before_creating_logs(self):
        self.invoke("--jobs", "0", success=False)
        self.assertFalse(list(self.source.glob("atlas-build-*")))

    def test_menu_selection_is_not_fixed(self):
        self.assertEqual(BUILD.gnu_dmpar_choice(
            " 7. (serial) 9. (dmpar) GNU (gfortran/gcc)\n"), "9")
        with self.assertRaises(BUILD.BuildError):
            BUILD.gnu_dmpar_choice(" 34. (dmpar) INTEL (ifort/icc)\n")

    def test_runner_requires_v422_and_comparison_flags(self):
        (self.source / "main").mkdir()
        (self.source / "run").mkdir()
        self.write_executable(self.source / "main/wrf.exe", "#!/bin/sh\nexit 0\n")
        archive = self.root / "not-the-official-archive.tar.gz"
        archive.write_text("deliberately invalid archive")
        runner = SCRIPT.with_name("run-conus-v42.sh")
        cases = [
            ("fb60d61cc44e2a2e8b8311f0b79185724010d510", "znver4", 3, "archive checksum"),
            ("6233639c599119e76fca17dba9ea211af53a0ba9", "znver4", 2, "v4.2.2 commit"),
            ("fb60d61cc44e2a2e8b8311f0b79185724010d510", "znver2", 2, "optimization flags"),
        ]
        for commit, target, code, message in cases:
            with self.subTest(commit=commit, target=target):
                (self.source / "configure.wrf").write_text(
                    f"FCOPTIM = -O3 -march={target} -Ofast -ftree-vectorize -funroll-loops\n")
                result = subprocess.run(
                    ["bash", str(runner), str(self.source), str(archive), str(self.root / "run")],
                    env={**self.env, "FAKE_GIT_COMMIT": commit}, capture_output=True,
                    text=True, timeout=10,
                )
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertIn(message, result.stderr)
                self.assertFalse((self.root / "run").exists())


if __name__ == "__main__":
    unittest.main()
