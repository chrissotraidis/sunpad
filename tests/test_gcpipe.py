"""Exercise controller-pipe connection using synthetic FIFOs only."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/gcpipe.py"
SPEC = importlib.util.spec_from_file_location("gcpipe", SCRIPT)
gcpipe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gcpipe)


class PadWriterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sunpad pipe ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.pipe = self.root / "controller"

    def assert_connection_times_out(self):
        # Keep a regression of the old blocking open from hanging the suite.
        try:
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--pipe", str(self.pipe),
                 "--open-timeout", "0.05", "--tap", "A"],
                capture_output=True, text=True, timeout=1.5)
        except subprocess.TimeoutExpired:
            self.fail("FIFO connection exceeded its open timeout")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pipe never opened for reading", result.stderr)

    def test_missing_pipe_times_out(self):
        self.assert_connection_times_out()

    def test_existing_fifo_without_reader_times_out(self):
        os.mkfifo(self.pipe)
        self.assert_connection_times_out()

    def test_short_timeout_does_not_wait_a_full_poll_interval(self):
        clock = [10.0]

        def sleep(seconds):
            clock[0] += seconds

        with mock.patch.object(gcpipe.time, "monotonic", side_effect=lambda: clock[0]), \
                mock.patch.object(gcpipe.time, "sleep", side_effect=sleep):
            with self.assertRaisesRegex(RuntimeError, "pipe never opened"):
                gcpipe.PadWriter(self.pipe, timeout_s=0.05)
        self.assertAlmostEqual(clock[0], 10.05)

    def test_delayed_reader_receives_commands_with_blocking_writer(self):
        os.mkfifo(self.pipe)
        code = """
import os
from pathlib import Path
import runpy
import sys
writer = runpy.run_path(sys.argv[1])["PadWriter"](Path(sys.argv[2]), timeout_s=2)
try:
    assert os.get_blocking(writer.fd), "connected writes must remain blocking"
    writer.tap("A", hold_s=0)
    writer.set_stick("MAIN", 0.5, -0.5)
    writer.set_trigger("R", 1)
finally:
    writer.close()
"""
        process = subprocess.Popen(
            [sys.executable, "-c", code, str(SCRIPT), str(self.pipe)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            time.sleep(0.15)
            self.assertIsNone(process.poll(), "writer did not wait for a reader")
            reader = os.open(self.pipe, os.O_RDONLY | os.O_NONBLOCK)
            try:
                stdout, stderr = process.communicate(timeout=3)
                self.assertEqual(process.returncode, 0, stdout + stderr)
                self.assertEqual(
                    os.read(reader, 4096),
                    b"PRESS A\nRELEASE A\nSET MAIN 0.750 0.750\nSET R 1.000\n")
            finally:
                os.close(reader)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_unexpected_open_error_is_not_retried(self):
        with mock.patch.object(gcpipe.time, "sleep") as sleep:
            with self.assertRaises(IsADirectoryError):
                gcpipe.PadWriter(self.root, timeout_s=1)
        sleep.assert_not_called()


if __name__ == "__main__":
    unittest.main()
