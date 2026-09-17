import os
from pathlib import Path
import subprocess
import tempfile
import unittest


CHECKER = Path(__file__).resolve().parents[1] / "scripts/check-topology.sh"


def topology():
    rows = ["CPU NODE SOCKET CORE L1d:L1i:L2:L3 ONLINE"]
    for cpu in range(176):
        node = cpu // 44
        private = cpu + (0, 4, 40, 44)[node]
        l3 = (0, 6, 16, 22)[node] + min((cpu % 44) // 8, 5)
        rows.append(f"{cpu} {node} {cpu // 88} {cpu} {private}:{private}:{private}:{l3} yes")
    return "\n".join(rows) + "\n"


class TopologyTests(unittest.TestCase):
    def run_checker(self, text, lscpu_status=0):
        with tempfile.TemporaryDirectory(prefix="topology test ") as directory:
            root = Path(directory)
            fixture = root / "lscpu.txt"
            fixture.write_text(text)
            command = root / "lscpu"
            command.write_text(
                '#!/bin/sh\n'
                '[ "$LC_ALL" = C ] || exit 2\n'
                'cat "$TOPOLOGY_FIXTURE"\n'
                'exit "$LSCPU_STATUS"\n')
            command.chmod(0o755)
            return subprocess.run(
                ["bash", str(CHECKER)],
                env={**os.environ, "PATH": f"{root}:/usr/bin:/bin",
                     "TOPOLOGY_FIXTURE": str(fixture), "LSCPU_STATUS": str(lscpu_status)},
                capture_output=True, text=True)

    def test_exact_signature_passes(self):
        proc = self.run_checker(topology())
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("PASS:", proc.stdout)

    def test_signature_mismatches_fail(self):
        rows = topology().splitlines()
        candidates = [
            "",
            "\n".join(rows[:-1]),
            "\n".join([*rows[:-1], rows[1]]),
            topology().replace("0 0 0 0 0:0:0:0 yes", "0 1 0 0 0:0:0:0 yes"),
            topology().replace("0 0 0 0 0:0:0:0 yes", "0 0 1 0 0:0:0:0 yes"),
            topology().replace("0 0 0 0 0:0:0:0 yes", "0 0 0 1 0:0:0:0 yes"),
            topology().replace("0:0:0:0", "1:1:1:0"),
            topology().replace("0:0:0:0", "0:0:0:1"),
            topology().replace("yes", "no", 1),
            topology().replace("0 0 0 0", "176 0 0 0", 1),
            topology().replace("0 0 0 0", "0 x 0 0", 1),
            topology().replace("0 0 0 0", "0 0 0", 1),
            topology().replace("L1d:L1i:L2:L3", "CACHE_ID"),
        ]
        for text in candidates:
            with self.subTest(text=text[:80]):
                proc = self.run_checker(text)
                self.assertNotEqual(proc.returncode, 0)
                self.assertIn("ERROR:", proc.stderr)
                self.assertNotIn("PASS:", proc.stdout)

    def test_order_does_not_matter(self):
        rows = topology().splitlines()
        proc = self.run_checker("\n".join([rows[0], *reversed(rows[1:])]))
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_generic_cache_column_label(self):
        proc = self.run_checker(topology().replace("L1d:L1i:L2:L3", "CACHE"))
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_lscpu_failure_cannot_report_success(self):
        proc = self.run_checker(topology(), lscpu_status=1)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Could not collect", proc.stderr)
        self.assertNotIn("PASS:", proc.stdout)


if __name__ == "__main__":
    unittest.main()
