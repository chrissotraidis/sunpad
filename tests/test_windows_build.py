"""Windows builder parity fixtures: no disc data, dependencies or compilation.

scripts/windows/build.py reimplements the Mac/Linux checks in Python; these cases keep
its disc, job-limit and generated-code checks equal to the shell scripts'.
"""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sunpad_windows_build", SOURCE / "scripts/windows/build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)

CORRECTED = ("ppc_fp_available_inline(ctx);\nppc_psq_load_inline(ctx);\nppc_psq_store_inline(ctx);\n"
             "ppc_fdivs(ctx);\nppc_ps_madd_op(ctx);\n")


def exit_code(function, *args):
    """function's SystemExit code and stderr, or (0, stderr) when it returns."""
    stderr = io.StringIO()
    with contextlib.redirect_stderr(stderr), contextlib.redirect_stdout(io.StringIO()):
        try:
            function(*args)
        except SystemExit as stop:
            return stop.code, stderr.getvalue()
    return 0, stderr.getvalue()


class WindowsBuilderTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="sun windows ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)

    def test_disc_and_shell_hashes_agree(self):
        shell = (SOURCE / "scripts/prepare-game.sh").read_text()
        self.assertIn(f"EXPECTED_SHA256={build.EXPECTED_SHA256}\n", shell)
        self.assertIn(f"= {build.GAME_FILES}\n", shell)

    def test_generated_audit_matches_the_shell_audit(self):
        gen = self.root / "generated"
        (gen / "chunks").mkdir(parents=True)
        (gen / "generated.c").touch()
        (gen / "generated.h").touch()
        chunk = gen / "chunks/corrected.c"
        cases = [
            (CORRECTED, 0),
            (CORRECTED + "ctx->fpr[2] = (f64)(f32)(ctx->fpr[2] / ctx->fpr[0]);\n", 1),
            (CORRECTED + "ppc_fp_available(ctx);\n", 1),
            (CORRECTED.replace("ppc_fdivs(ctx);\n", ""), 1),
        ]
        for content, expected in cases:
            with self.subTest(content=content[-50:]):
                chunk.write_text(content)
                shell = subprocess.run([str(SOURCE / "scripts/audit-generated-gmse01.sh"), str(gen)],
                                       capture_output=True, text=True).returncode
                python, _ = exit_code(build.audit_generated, gen)
                self.assertEqual((shell, python), (expected, expected))

    def test_job_limits_match_the_shell_rules(self):
    def test_translated_sources_get_unix_line_endings(self):
        gen = self.root / "generated"
        (gen / "chunks").mkdir(parents=True)
        (gen / "chunks/a.c").write_bytes(b"int a;\r\nint b;\r\n")
        (gen / "generated_smc.txt").write_bytes(b"x\r\n")
        (gen / "main.dol").write_bytes(b"\r\n\x00")
        build.unix_line_endings(gen)
        self.assertEqual((gen / "chunks/a.c").read_bytes(), b"int a;\nint b;\n")
        self.assertEqual((gen / "generated_smc.txt").read_bytes(), b"x\n")
        self.assertEqual((gen / "main.dol").read_bytes(), b"\r\n\x00")

    def test_job_limits_match_the_shell_rules(self):
        for value, expected in (("2", 0), ("12", 0), ("0", 2), ("-1", 2), ("02", 2), ("1.5", 2),
                                ("2 3", 2), ("abc", 2), (" 2", 2), ("2\n", 2)):
            with self.subTest(value=value), mock.patch.dict(build.os.environ, {"SUNPAD_JOBS": value}):
                self.assertEqual(exit_code(build.jobs)[0], expected)
        with mock.patch.dict(build.os.environ, {"SUNPAD_JOBS": "", "CMAKE_BUILD_PARALLEL_LEVEL": ""}):
            self.assertEqual(build.jobs(), "8")
        with mock.patch.dict(build.os.environ, {"SUNPAD_JOBS": "3", "CMAKE_BUILD_PARALLEL_LEVEL": "x"}):
            self.assertEqual(build.jobs(), "3")

    def test_wrong_disc_stops_before_sources_or_tools(self):
        disc = self.root / "synthetic not a disc.iso"
        disc.write_bytes(b"not a disc")
        with mock.patch.object(build, "dependencies") as deps, \
                mock.patch.object(build, "visual_studio_env") as studio, \
                mock.patch.dict(build.os.environ, {"SUNPAD_JOBS": "2"}):
            code, stderr = exit_code(build.prepare, disc)
        self.assertEqual(code, 1)
        self.assertIn("unsupported disc image SHA-256", stderr)
        deps.assert_not_called()
        studio.assert_not_called()

    def test_module_needs_prepared_sources(self):
        with mock.patch.object(build, "MODULES", self.root / "modules"), \
                mock.patch.object(build, "run") as run, \
                mock.patch.dict(build.os.environ, {"SUNPAD_JOBS": "2"}):
            code, stderr = exit_code(build.module, self.root / "toolchain.cmake", self.root / "out")
        self.assertEqual(code, 1)
        self.assertIn("prepared module sources missing", stderr)
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
