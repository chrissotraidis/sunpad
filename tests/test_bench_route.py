"""Exercise the benchmark's process handling without game data or a renderer."""

import csv
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BenchRouteTests(unittest.TestCase):
    def run_benchmark(self, mode):
        with tempfile.TemporaryDirectory(prefix="sunpad-bench-test-") as temp:
            root = Path(temp)
            script = root / "scripts/bench-route.sh"
            script.parent.mkdir()
            shutil.copyfile(ROOT / "scripts/bench-route.sh", script)
            runner = root / "ref/ModernGekko/build-desktop-tools-public/moderngekko-run"
            runner.parent.mkdir(parents=True)
            runner.write_text("""#!/usr/bin/env python3
import os, signal, time
from pathlib import Path
signal.signal(signal.SIGINT, lambda *_: exit(0))
log = Path(os.environ['BENCH_TEST_LOG'])
mode = os.environ['BENCH_TEST_MODE']
print('[warp] entered stage 9', flush=True)
while True:
    text = log.read_text()
    if '[bench] settle-start' in text and mode == 'settle':
        exit(37)
    if '[bench] measure-start' in text:
        print('[perf] t=5.0 fps=60.00 vps=120.00 speed=2.0000 '
              'efb_copies=25 efb_immediate=0 efb_wait_pct=10.00', flush=True)
        if mode == 'measure':
            exit(42)
    time.sleep(0.02)
""")
            runner.chmod(0o755)
            dol = root / "ref/ModernGekko-Template/extracted/Super-Mario-Sunshine/sys/main.dol"
            dol.parent.mkdir(parents=True)
            dol.touch()
            module = root / "fixture-module.dylib"
            module.touch()
            active = root / "ref/ModernGekko-Template/build/modules-macos14/GMSE01/active-module.txt"
            active.parent.mkdir(parents=True)
            active.write_text(str(module))
            bin_dir = root / "bin"
            bin_dir.mkdir()
            git = bin_dir / "git"
            git.write_text("#!/bin/sh\necho fixture\n")
            git.chmod(0o755)
            env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
                       BENCH_TEST_MODE=mode,
                       BENCH_TEST_LOG=str(root / "artifacts/bench/test-noki.log"))
            result = subprocess.run(
                ["bash", str(script), "noki", "test", "0.3", "0.3"],
                env=env, capture_output=True, text=True, timeout=8,
            )
            csv_path = root / "artifacts/bench/results.csv"
            rows = []
            if csv_path.exists():
                with csv_path.open() as handle:
                    rows = list(csv.DictReader(handle))
            log = Path(env["BENCH_TEST_LOG"]).read_text()
            return result, rows, log

    def test_complete_run_writes_one_result(self):
        result, rows, log = self.run_benchmark("complete")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["vps"], "120.0")
        self.assertIn("[bench] measure-end", log)

    def test_exit_during_settle_does_not_write_result(self):
        result, rows, log = self.run_benchmark("settle")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runner exited (status 37)", result.stderr)
        self.assertEqual(rows, [])
        self.assertNotIn("[bench] measure-start", log)

    def test_exit_after_measurement_row_does_not_write_partial_result(self):
        result, rows, log = self.run_benchmark("measure")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runner exited (status 42)", result.stderr)
        self.assertEqual(rows, [])
        self.assertIn("[perf]", log)
        self.assertNotIn("[bench] measure-end", log)


if __name__ == "__main__":
    unittest.main()
