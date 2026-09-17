import importlib.util
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
spec = importlib.util.spec_from_file_location("stream_summary", SCRIPTS / "summarize.py")
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


def output():
    header = """This system uses 8 bytes per array element.
Array size = 650000000 (elements), Offset = 0 (elements)
Each kernel will be executed 10 times.
Number of Threads requested = 176
Number of Threads counted = 176
"""
    binding = "".join(f"OMP: pid 1 tid {i+1} thread {i} bound to OS proc set {{{i}}}\n"
                      for i in range(176))
    rates = "Function    Best Rate MB/s  Avg time     Min time     Max time\n"
    rates += "".join(f"{kernel}: 750000.0 0.022 0.020 0.026\n" for kernel in summary.KERNELS)
    return header + binding + rates + "Solution Validates: avg error less than 1e-13\n"


class SummaryTests(unittest.TestCase):
    def test_cpu_lists(self):
        self.assertEqual(summary.parse_cpu_list("0-3,44,88-89"), [0, 1, 2, 3, 44, 88, 89])
        for value in ("", "0-176", "3-1", "0,0", "0-1,1", "-1", "0;1"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                summary.parse_cpu_list(value)

    def test_smaller_thread_team(self):
        text = output().replace("Threads requested = 176", "Threads requested = 2")
        text = text.replace("Threads counted = 176", "Threads counted = 2")
        text = "\n".join(line for line in text.splitlines() if not line.startswith("OMP:"))
        text += "\nOMP: pid 1 tid 1 thread 0 bound to OS proc set {0}\n"
        text += "OMP: pid 1 tid 2 thread 1 bound to OS proc set {88}\n"
        record = summary.parse_log(text, [0, 88])
        self.assertEqual(record["workload"]["cpu_ids"], [0, 88])
        self.assertAlmostEqual(record["average_rate_MB_s"]["Triad"], 650000000 * 24 / .022 / 1e6)
        with self.assertRaises(ValueError):
            summary.parse_log(text, [0, 44])

    def test_success_and_variance(self):
        first = summary.parse_log(output())
        second = summary.parse_log(output().replace("750000.0", "760000.0"))
        result = summary.summarize([first, second])
        self.assertEqual(result["metrics"]["Triad"]["median_MB_s"], 755000)
        self.assertAlmostEqual(result["metrics"]["Triad"]["range_percent_of_median"],
                               100 * 10000 / 755000)
        self.assertEqual(result["repetitions"], 2)
        self.assertEqual(result["scope"],
                         "Workload-specific STREAM bandwidth; compare matching array sizes and run settings")
        json.dumps(result, allow_nan=False)

    def test_bad_outputs(self):
        for text in (
            output().replace("Solution Validates:", "No validation:"),
            output() + "Failed Validation on array a[]\n",
            output().replace("750000.0", "nan"),
            output().replace("750000.0", "-3"),
            output().replace("0.022 0.020", "0.019 0.020"),
            output().replace("Threads counted = 176", "Threads counted = 88"),
            output().replace("8 bytes", "4 bytes"),
            output().replace("10 times", "1 times"),
            output().replace("Best Rate MB/s", "Best Rate GB/s"),
            output().replace("set {175}", "set {0}"),
            output().replace("set {175}", "set {0-175}"),
            output().replace("thread 175", "thread 174"),
            output() + "Copy: 750000.0 0.022 0.020 0.026\n",
        ):
            with self.subTest(text=text[-100:]), self.assertRaises(ValueError):
                summary.parse_log(text)

    def test_mismatched_workload(self):
        for old, new in (("650000000", "280000000"), ("10 times", "100 times")):
            with self.assertRaisesRegex(ValueError, "dimensions differ"):
                summary.summarize([summary.parse_log(output()),
                                   summary.parse_log(output().replace(old, new))])

    def test_cli_fails_without_success_json(self):
        with tempfile.TemporaryDirectory() as root:
            log = Path(root) / "bad.log"
            log.write_text("Solution Validates:\n")
            proc = subprocess.run([sys.executable, str(SCRIPTS / "summarize.py"), str(log)],
                                  capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertEqual(proc.stdout, "")
            self.assertIn("ERROR:", proc.stderr)

    def test_cli_rejects_wrong_profile_dimensions(self):
        with tempfile.TemporaryDirectory() as root:
            log = Path(root) / "stream.log"
            log.write_text(output())
            proc = subprocess.run([sys.executable, str(SCRIPTS / "summarize.py"),
                                   "--expected-array-elements", "280000000", str(log)],
                                  capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("Unexpected array_elements", proc.stderr)
            self.assertEqual(proc.stdout, "")

    def test_scripts_require_approval(self):
        for name, args in (("build-stream.sh", ["aocc", "stream.c", "build"]),
                           ("run-stream.sh", ["stream", "run"])):
            proc = subprocess.run(["bash", str(SCRIPTS / name), *args],
                                  env={"PATH": "/usr/bin:/bin"}, capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("ERROR:", proc.stderr)


class HelperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="stream test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.tools = self.root / "tools"
        self.tools.mkdir()

    def tool(self, directory, name, code):
        path = directory / name
        path.write_text(f"#!{sys.executable}\n" + code)
        path.chmod(0o755)
        return path

    def build(self, mode="ok", original=False):
        aocc = self.root / "aocc"
        (aocc / "bin").mkdir(parents=True)
        (aocc / "lib").mkdir()
        self.tool(aocc / "bin", "clang", """
from pathlib import Path
import os
import sys
if '--version' in sys.argv:
    print('AMD clang version 14.0.6 AOCC_4.0.0')
elif os.environ.get('FAKE_MODE') == 'fail':
    print('unsupported option', file=sys.stderr)
    sys.exit(7)
else:
    original = os.environ.get('FAKE_ORIGINAL') == 'yes'
    assert ('-DSTREAM_ARRAY_SIZE=280000000' if original else '-DSTREAM_ARRAY_SIZE=650000000') in sys.argv
    assert ('-DNTIMES=100' if original else '-DNTIMES=10') in sys.argv
    assert '-fvector-transform' in sys.argv
    path = Path(sys.argv[sys.argv.index('-o') + 1])
    path.write_text('#!/bin/sh\\nexit 0\\n')
    path.chmod(0o755)
""")
        self.tool(aocc / "bin", "ldd", "print('libc.so.6 => /lib/libc.so.6 (0x123)')\n")
        self.tool(aocc / "bin", "lscpu", "print('Model name: test CPU')\n")
        source = self.root / "stream.c"
        source.write_text("test source")
        build = self.root / "build"
        env = {**os.environ, "STREAM_LICENSE_ACCEPTED": "yes",
               "STREAM_RELAXED_FP_APPROVED": "yes", "STREAM_ARRAY_SIZE": "650000000",
               "STREAM_NTIMES": "10", "FAKE_MODE": mode,
               "FAKE_ORIGINAL": "yes" if original else "no"}
        if original:
            env.pop("STREAM_ARRAY_SIZE", None)
            env.pop("STREAM_NTIMES", None)
        proc = subprocess.run(["bash", str(SCRIPTS / "build-stream.sh"), str(aocc),
                               str(source), str(build)], env=env, capture_output=True, text=True)
        return proc, build

    def test_build_profile_and_provenance(self):
        proc, build = self.build()
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        manifest = (build / "build-manifest.txt").read_text()
        self.assertIn("array_size=650000000", manifest)
        self.assertIn("ntimes=10", manifest)
        self.assertIn("-fnt-store", manifest)
        self.assertTrue((build / "stream").is_file())
        self.assertEqual((build / "stream.c").read_text(), "test source")

    def test_compiler_failure_retains_log(self):
        proc, build = self.build("fail")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("unsupported option", (build / "build.log").read_text())
        self.assertFalse((build / "stream").exists())

    def test_build_defaults_preserve_original_workload(self):
        proc, build = self.build(original=True)
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        manifest = (build / "build-manifest.txt").read_text()
        self.assertIn("array_size=280000000", manifest)
        self.assertIn("ntimes=100", manifest)
        command = next(line.removeprefix("command=") for line in manifest.splitlines()
                       if line.startswith("command="))
        self.assertEqual(shlex.split(command)[2:-2], [
            "-fopenmp", "-mcmodel=large", "-DSTREAM_TYPE=double",
            "-DSTREAM_ARRAY_SIZE=280000000", "-DNTIMES=100", "-ffp-contract=fast",
            "-fnt-store", "-O3", "-Ofast", "-ffast-math", "-ffinite-loops",
            "-march=native", "-zopt", "-fremap-arrays", "-mllvm",
            "-enable-strided-vectorization", "-fvector-transform",
        ])

    def run_candidate(self, text, exit_code, profile="normalized-176",
                      thp_approved=False, fail_thp=False, prebuilt_checksum_valid=True,
                      cache_drop_approved=False, fail_cache_drop=False, repetitions=1,
                      inject_prebuilt_runtime=False, allowed_cpus="0-175",
                      available_kib=32 * 1024 * 1024, numa_policy="default",
                      bad_topology=False, avx512=True, fail_restore=False):
        explicit_profile = profile
        profile = profile or "source-original"
        self.tool(self.tools, "curl", "print('Standard_HB176rs_v4')\n")
        self.tool(self.tools, "python3", f"""
import os
import sys
assert sys.argv[1:] != ['-'], 'Preflight must not embed Python'
os.execv({sys.executable!r}, [{sys.executable!r}, *sys.argv[1:]])
""")
        topology = "CPU NODE SOCKET CORE L1d:L1i:L2:L3 ONLINE\n"
        for cpu in range(176):
            node = cpu // 44
            private = cpu + (0, 4, 40, 44)[node]
            l3 = (0, 6, 16, 22)[node] + min((cpu % 44) // 8, 5)
            topology += f"{cpu} {node} {cpu // 88} {cpu} {private}:{private}:{private}:{l3} yes\n"
        if bad_topology:
            topology = topology.replace("0:0:0:0", "0:0:0:1")
        self.tool(self.tools, "lscpu", f"print({topology!r}, end='')\n")
        self.tool(self.tools, "numactl", f"print({'policy: ' + numa_policy!r})\n")
        for name in ("vmstat", "sync"):
            self.tool(self.tools, name, "print('mock inventory')\n")
        (self.root / "proc-status").write_text(
            f"Cpus_allowed_list:\t{allowed_cpus}\nMems_allowed_list:\t0-3\n")
        (self.root / "proc-memory").write_text(f"MemAvailable: {available_kib} kB\n")
        (self.root / "proc-cpuinfo").write_text("flags: avx512f\n" if avx512 else "flags: avx2\n")
        for name in ("awk", "grep"):
            self.tool(self.tools, name, f"""
import os
import sys
paths = {{'/proc/self/status': {str(self.root / 'proc-status')!r},
          '/proc/meminfo': {str(self.root / 'proc-memory')!r},
          '/proc/cpuinfo': {str(self.root / 'proc-cpuinfo')!r}}}
args = [paths.get(arg, arg) for arg in sys.argv[1:]]
os.execv('/usr/bin/{name}', ['/usr/bin/{name}', *args])
""")
        library = self.root / "lib test.so"
        library.write_text("test library")
        self.tool(self.tools, "env", f"""
import sys
if 'ldd' in sys.argv:
    print({'libtest.so => ' + str(library) + ' (0x123)'!r})
else:
    from pathlib import Path
    Path({str(self.root / 'launch-args.json')!r}).write_text(__import__('json').dumps(sys.argv))
    print({text!r})
    sys.exit({exit_code})
""")
        binary = self.tool(self.root, "stream", "raise AssertionError('Use mocked launcher')\n")
        arguments = []
        if profile in ("source-original", "prebuilt-original", "tuned-144", "prebuilt-144"):
            lib_dir = self.root / "runtime"
            lib_dir.mkdir()
            (lib_dir / "libomp.so").write_text("test runtime")
            arguments = [str(lib_dir)] if profile in ("source-original", "tuned-144") else []
            if inject_prebuilt_runtime:
                arguments = [str(lib_dir)]
            (self.root / "stream.c").write_text("test source")
            (self.root / "compiler-version.txt").write_text("AOCC_4.0.0-Build#434")
            (self.root / "build-manifest.txt").write_text(
                "array_size=280000000\nntimes=100\n"
                + hashlib.sha256(binary.read_bytes()).hexdigest() + "  " + str(binary) + "\n")
            prebuilt_hash = ("b6d034f991c560f3f1edfb4da23dd73d11e864878eb60956d2b46e412984f6c0"
                             if prebuilt_checksum_valid else "0" * 64)
            self.tool(self.tools, "sha256sum", """
from pathlib import Path
import hashlib
import sys
for value in sys.argv[1:]:
    path = Path(value)
    known = {'stream.c': 'c388924eb140fda95f534cdb808ae7f1f8ebb18da41d8aec1b512a3c8d303c9b',
             'libomp.so': 'b62fd9fa42dc0d19131cf3368f914d77004cf7200aed710c91a3b97ba92ffef6'}
""" + (f"    known['stream'] = {prebuilt_hash!r}\n" if profile.startswith("prebuilt-") else "") + """
    print(known.get(path.name, hashlib.sha256(path.read_bytes()).hexdigest()) + '  ' + value)
""")
            for setting in ("enabled", "defrag"):
                (self.root / setting).write_text("always [madvise] never\n")
            for name in ("sed", "cat"):
                self.tool(self.tools, name, f"""
import os
import sys
from pathlib import Path
args = [str(Path({str(self.root)!r}) / Path(a).name)
        if a.startswith('/sys/kernel/mm/transparent_hugepage/') else a
        for a in sys.argv[1:]]
os.execv('/usr/bin/{name}', ['/usr/bin/{name}', *args])
""")
            self.tool(self.tools, "sudo", f"""
from pathlib import Path
import sys
if sys.argv[1:] == ['-n', 'true']:
    sys.exit(0)
assert sys.argv[1:3] == ['-n', 'tee'], sys.argv
target = Path(sys.argv[3])
value = sys.stdin.read().strip()
if str(target) == '/proc/sys/vm/drop_caches':
    assert value == '3'
    if {fail_cache_drop!r}:
        print('simulated cache-drop failure', file=sys.stderr)
        sys.exit(1)
    with Path({str(self.root / 'cache-drops.txt')!r}).open('a') as log:
        log.write(value + '\\n')
    sys.exit(0)
assert str(target.parent) == '/sys/kernel/mm/transparent_hugepage', target
if {fail_thp!r} and target.name == 'defrag' and value == 'always':
    print('simulated setting failure', file=sys.stderr)
    sys.exit(1)
if {fail_restore!r} and value == 'madvise':
    print('simulated restoration failure', file=sys.stderr)
    sys.exit(1)
Path({str(self.root)!r}, target.name).write_text('[' + value + ']\\n')
""")
        run = self.root / "run"
        env = {**os.environ, "PATH": f"{self.tools}:/usr/bin:/bin",
               "STREAM_RUN_APPROVED": "yes", "STREAM_PROFILE": profile,
               "STREAM_THP_APPROVED": "yes" if thp_approved else "no",
               "STREAM_CACHE_DROP_APPROVED": "yes" if cache_drop_approved else "no"}
        if explicit_profile is None:
            env.pop("STREAM_PROFILE", None)
        proc = subprocess.run(["bash", str(SCRIPTS / "run-stream.sh"), str(binary),
                               str(run), str(repetitions), *arguments],
                              env=env, capture_output=True, text=True)
        return proc, run

    def tuned_output(self):
        cpus = [node * 44 + offset + i for node in range(4)
                for offset in (0, 8, 16, 24, 32, 38) for i in range(6)]
        text = output().replace("650000000", "280000000").replace("10 times", "100 times")
        text = text.replace("= 176", "= 144")
        text = "\n".join(line for line in text.splitlines() if not line.startswith("OMP:"))
        text += "\n" + "".join(f"OMP: pid 1 tid {i+1} thread {i} bound to OS proc set {{{cpu}}}\n"
                                for i, cpu in enumerate(cpus))
        return text, cpus

    def test_tuned_profile_success_and_restore(self):
        text, cpus = self.tuned_output()
        proc, run = self.run_candidate(text, 0, "tuned-144", True)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        result = json.loads((run / "summary.json").read_text())
        self.assertEqual(result["workload"]["cpu_ids"], cpus)
        args = json.loads((self.root / "launch-args.json").read_text())
        self.assertIn("OMP_NUM_THREADS=144", args)
        self.assertTrue(any(a.startswith("GOMP_CPU_AFFINITY=") for a in args))
        self.assertFalse(any(a.startswith(("OMP_PLACES=", "OMP_PROC_BIND=")) for a in args))
        self.assertNotIn("numactl", args)
        self.assertEqual((run / "thp-active.txt").read_text(), "[always]\n[always]\n")
        self.assertEqual((run / "thp-restored.txt").read_text(), "[madvise]\n[madvise]\n")
        self.assertFalse((self.root / "cache-drops.txt").exists())

    def test_unspecified_profile_uses_original_source(self):
        text = output().replace("650000000", "280000000").replace("10 times", "100 times")
        proc, run = self.run_candidate(text, 0, None, True, cache_drop_approved=True,
                                       repetitions=3)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        args = json.loads((self.root / "launch-args.json").read_text())
        for setting in ("OMP_NUM_THREADS=176", "GOMP_CPU_AFFINITY=0-175",
                        "OMP_SCHEDULE=static", "OMP_DYNAMIC=false",
                        "OMP_THREAD_LIMIT=512", "OMP_STACKSIZE=256M"):
            self.assertIn(setting, args)
        self.assertFalse(any(a.startswith(("OMP_PLACES=", "OMP_PROC_BIND=")) for a in args))
        self.assertNotIn("numactl", args)
        self.assertEqual((self.root / "cache-drops.txt").read_text(), "3\n" * 3)
        self.assertEqual(json.loads((run / "summary.json").read_text())["repetitions"], 3)
        self.assertIn("profile=source-original", (run / "run-manifest.txt").read_text())
        commands = [line.removeprefix("command=")
                    for line in (run / "run-manifest.txt").read_text().splitlines()
                    if line.startswith("command=")]
        self.assertEqual(len(commands), 3)
        self.assertEqual(shlex.split(commands[0])[1:], args[1:])
        self.assertEqual((run / "thp-active.txt").read_text(), "[always]\n[always]\n")
        self.assertEqual((run / "thp-restored.txt").read_text(), "[madvise]\n[madvise]\n")

    def test_original_source_requires_cache_drop_approval(self):
        proc, run = self.run_candidate(output(), 0, "source-original", True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("STREAM_CACHE_DROP_APPROVED", proc.stderr)
        self.assertFalse(run.exists())
        self.assertFalse((self.root / "cache-drops.txt").exists())

    def test_original_source_requires_thp_approval(self):
        proc, run = self.run_candidate(output(), 0, None, cache_drop_approved=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("STREAM_THP_APPROVED", proc.stderr)
        self.assertFalse(run.exists())

    def test_original_source_rejects_wrong_dimensions_and_restores(self):
        proc, run = self.run_candidate(output(), 0, "source-original", True,
                                       cache_drop_approved=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Unexpected array_elements", proc.stderr)
        self.assertFalse((run / "summary.json").exists())
        self.assertEqual((run / "thp-restored.txt").read_text(), "[madvise]\n[madvise]\n")

    def test_original_source_cache_drop_failure_restores_thp(self):
        proc, run = self.run_candidate(output(), 0, "source-original", True,
                                       cache_drop_approved=True, fail_cache_drop=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("simulated cache-drop failure", proc.stderr)
        self.assertFalse((run / "stream-1.log").exists())
        self.assertEqual((run / "thp-restored.txt").read_text(), "[madvise]\n[madvise]\n")

    def test_original_prebuilt_uses_only_original_omp_controls(self):
        proc, run = self.run_candidate(output(), 0, "prebuilt-original", True)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        args = json.loads((self.root / "launch-args.json").read_text())
        for setting in ("OMP_NUM_THREADS=176", "OMP_PROC_BIND=true", "OMP_PLACES=cores"):
            self.assertIn(setting, args)
        self.assertFalse(any(a.startswith(("GOMP_", "OMP_SCHEDULE=", "OMP_DYNAMIC=",
                                          "OMP_THREAD_LIMIT=", "OMP_STACKSIZE=",
                                          "LD_LIBRARY_PATH=")) for a in args))
        self.assertNotIn("numactl", args)
        self.assertFalse((self.root / "cache-drops.txt").exists())
        self.assertEqual((run / "thp-active.txt").read_text(), "[always]\n[always]\n")
        self.assertEqual((run / "thp-restored.txt").read_text(), "[madvise]\n[madvise]\n")
        self.assertIn("command=env -i", (run / "run-manifest.txt").read_text())

    def test_original_prebuilt_requires_thp_approval(self):
        proc, run = self.run_candidate(output(), 0, "prebuilt-original")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("STREAM_THP_APPROVED", proc.stderr)
        self.assertFalse(run.exists())

    def test_original_prebuilt_rejects_runtime_injection(self):
        proc, run = self.run_candidate(output(), 0, "prebuilt-original", True,
                                       inject_prebuilt_runtime=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("must not inject", proc.stderr)
        self.assertFalse(run.exists())

    def test_original_prebuilt_rejects_unknown_binary(self):
        proc, run = self.run_candidate(output(), 0, "prebuilt-original", True,
                                       prebuilt_checksum_valid=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Prebuilt executable differs", proc.stderr)
        self.assertFalse(run.exists())

    def test_original_prebuilt_rejects_wrong_iterations_and_restores(self):
        proc, run = self.run_candidate(output().replace("10 times", "100 times"), 0,
                                       "prebuilt-original", True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Unexpected ntimes", proc.stderr)
        self.assertFalse((run / "summary.json").exists())
        self.assertEqual((run / "thp-restored.txt").read_text(), "[madvise]\n[madvise]\n")

    def test_prebuilt_profile_success_and_restore(self):
        text, cpus = self.tuned_output()
        text = text.replace("280000000", "650000000").replace("100 times", "10 times")
        proc, run = self.run_candidate(text, 0, "prebuilt-144", True)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        result = json.loads((run / "summary.json").read_text())
        self.assertEqual(result["workload"]["cpu_ids"], cpus)
        self.assertEqual(result["workload"]["array_elements"], 650000000)
        self.assertEqual(result["workload"]["ntimes"], 10)
        args = json.loads((self.root / "launch-args.json").read_text())
        self.assertFalse(any(arg.startswith("LD_LIBRARY_PATH=") for arg in args))
        self.assertEqual((run / "thp-restored.txt").read_text(), "[madvise]\n[madvise]\n")

    def test_prebuilt_rejects_unknown_binary(self):
        proc, run = self.run_candidate(output(), 0, "prebuilt-144", True,
                                       prebuilt_checksum_valid=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Prebuilt executable differs", proc.stderr)
        self.assertFalse(run.exists())

    def test_prebuilt_rejects_source_dimensions(self):
        text, _ = self.tuned_output()
        proc, run = self.run_candidate(text, 0, "prebuilt-144", True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Unexpected array_elements", proc.stderr)
        self.assertFalse((run / "summary.json").exists())
        self.assertEqual((run / "thp-restored.txt").read_text(), "[madvise]\n[madvise]\n")

    def test_tuned_requires_separate_thp_approval(self):
        proc, run = self.run_candidate(output(), 0, "tuned-144", False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("STREAM_THP_APPROVED", proc.stderr)
        self.assertFalse(run.exists())

    def test_tuned_restores_after_benchmark_failure(self):
        proc, run = self.run_candidate("partial", 124, "tuned-144", True)
        self.assertEqual(proc.returncode, 124)
        self.assertEqual((run / "thp-restored.txt").read_text(), "[madvise]\n[madvise]\n")
        self.assertFalse((run / "summary.json").exists())

    def test_tuned_restores_partial_setting_change(self):
        proc, run = self.run_candidate("unused", 0, "tuned-144", True, fail_thp=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual((run / "thp-restored.txt").read_text(), "[madvise]\n[madvise]\n")
        self.assertFalse((run / "stream-1.log").exists())

    def test_tuned_rejects_wrong_binary_output_and_restores(self):
        proc, run = self.run_candidate(output(), 0, "tuned-144", True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual((run / "thp-restored.txt").read_text(), "[madvise]\n[madvise]\n")
        self.assertFalse((run / "summary.json").exists())

    def test_unknown_profile(self):
        proc, run = self.run_candidate(output(), 0, "unknown")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Unknown STREAM_PROFILE", proc.stderr)
        self.assertFalse(run.exists())

    def test_shared_topology_checker_blocks_bad_signature(self):
        proc, run = self.run_candidate(output(), 0, "prebuilt-original", True,
                                       bad_topology=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("topology differs", proc.stderr)
        self.assertFalse(run.exists())
        self.assertEqual((self.root / "enabled").read_text(), "always [madvise] never\n")

    def test_restricted_allocation_is_rejected(self):
        proc, run = self.run_candidate(output(), 0, allowed_cpus="0-143")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("all CPUs 0-175", proc.stderr)
        self.assertFalse(run.exists())

    def test_insufficient_memory_is_rejected(self):
        proc, run = self.run_candidate(output(), 0, available_kib=24 * 1024 * 1024 - 1)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("24 GiB", proc.stderr)
        self.assertFalse(run.exists())

    def test_exact_memory_threshold_is_accepted(self):
        proc, run = self.run_candidate(output(), 0, available_kib=24 * 1024 * 1024)
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        self.assertTrue((run / "summary.json").is_file())

    def test_missing_avx512_is_rejected(self):
        proc, run = self.run_candidate(output(), 0, avx512=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("AVX-512", proc.stderr)
        self.assertFalse(run.exists())

    def test_original_profile_rejects_inherited_numa_override(self):
        proc, run = self.run_candidate(output(), 0, "prebuilt-original", True,
                                       numa_policy="interleave")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("default NUMA policy", proc.stderr)
        self.assertFalse(run.exists())

    def test_normalized_profile_retains_explicit_numa_override(self):
        proc, run = self.run_candidate(output(), 0, numa_policy="interleave", bad_topology=True)
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        args = json.loads((self.root / "launch-args.json").read_text())
        self.assertIn("numactl", args)
        self.assertIn("--localalloc", args)
        self.assertFalse((run / "thp-restored.txt").exists())

    def test_restoration_failure_is_reported(self):
        proc, run = self.run_candidate(output(), 0, "prebuilt-original", True,
                                       fail_restore=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("THP restoration failed", proc.stderr)
        self.assertEqual((run / "thp-original.txt").read_text(), "enabled=madvise\ndefrag=madvise\n")

    def test_runner_success(self):
        proc, run = self.run_candidate(output(), 0)
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        self.assertEqual(json.loads((run / "summary.json").read_text())["repetitions"], 1)
        self.assertIn(hashlib.sha256(b"test library").hexdigest(),
                      (run / "libraries.sha256").read_text())

    def test_shell_library_hashes_handle_loader_and_spaces(self):
        library = self.root / "library with spaces.so"
        library.write_text("library")
        loader = self.root / "ld-linux.so"
        loader.write_text("loader")
        (self.root / "libraries.txt").write_text(
            "linux-vdso.so.1 (0x123)\n"
            f"\tlibtest.so => {library} (0x456)\n"
            f"\t{loader} (0xabc)\n")
        proc = subprocess.run(
            ["bash", "-c", 'set -euo pipefail; source "$1"; output=$2; record_library_hashes',
             "bash", str(SCRIPTS / "lib/records.sh"), str(self.root)],
            capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual((self.root / "libraries.sha256").read_text().splitlines(), [
            f"{hashlib.sha256(b'library').hexdigest()}  {library}",
            f"{hashlib.sha256(b'loader').hexdigest()}  {loader}",
        ])

    def test_zero_exit_with_failed_validation(self):
        proc, run = self.run_candidate(output() + "Failed Validation on array a[]", 0)
        self.assertNotEqual(proc.returncode, 0)
        self.assertTrue((run / "stream-1.log").is_file())
        self.assertFalse((run / "summary.json").exists())

    def test_timeout_status_not_hidden(self):
        proc, run = self.run_candidate("partial output", 124)
        self.assertEqual(proc.returncode, 124)
        self.assertIn("partial output", (run / "stream-1.log").read_text())
        self.assertFalse((run / "summary.json").exists())


class SkillTests(unittest.TestCase):
    def test_entry_skill_remains_concise(self):
        text = (SCRIPTS.parent / "SKILL.md").read_text()
        self.assertLessEqual(len(text.split()), 800)
        for profile in ("source-original", "prebuilt-original", "tuned-144", "prebuilt-144"):
            self.assertIn(f"STREAM_PROFILE={profile}",
                          text + (SCRIPTS.parent / "references/usage.md").read_text())

    def test_local_reference_links_resolve(self):
        for document in SCRIPTS.parent.rglob("*.md"):
            for target in re.findall(r"\]\(([^)]+)\)", document.read_text()):
                if "://" in target or target.startswith("#"):
                    continue
                path = document.parent / target.split("#", 1)[0]
                with self.subTest(document=document.name, target=target):
                    self.assertTrue(path.is_file(), str(path))


if __name__ == "__main__":
    unittest.main()
