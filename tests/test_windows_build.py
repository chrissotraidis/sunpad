"""Windows builder parity fixtures: no disc data, dependencies or compilation.

scripts/windows/build.py reimplements the Mac/Linux checks in Python; these cases keep
its disc, job-limit and generated-code checks equal to the shell scripts'.
"""
import contextlib
import importlib.util
import io
import json
import os
import shutil
import sys
from types import SimpleNamespace
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
        temp = tempfile.TemporaryDirectory(prefix="sun windows 雪 ")
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

    def test_module_starts_fresh_only_for_a_new_toolchain(self):
        gen = self.root / "modules/GMSE01/key/dolrecomp-output/generated"
        (gen / "chunks").mkdir(parents=True)
        (gen / "chunks/a.c").write_text(CORRECTED)
        for name in ("generated.c", "generated.h", "main.dol"):
            (gen / name).touch()
        toolchain, out = self.root / "toolchain.cmake", self.root / "out"
        out.mkdir()
        for cached, fresh in ((None, False), (toolchain, False), (self.root / "old.cmake", True)):
            if cached:
                (out / "CMakeCache.txt").write_text(f"CMAKE_TOOLCHAIN_FILE:FILEPATH={build.posix(cached)}\n")
            with self.subTest(cached=cached), mock.patch.object(build, "generated_dir", return_value=gen), \
                    mock.patch.object(build, "run") as run, mock.patch.dict(build.os.environ, {"SUNPAD_JOBS": "2"}):
                self.assertEqual(exit_code(build.module, toolchain, out)[0], 0)
                self.assertEqual("--fresh" in run.call_args_list[0][0][0], fresh)

    def test_module_needs_prepared_sources(self):
        with mock.patch.object(build, "TRANSLATION", self.root / "modules"), \
                mock.patch.object(build, "run") as run, \
                mock.patch.dict(build.os.environ, {"SUNPAD_JOBS": "2"}):
            code, stderr = exit_code(build.module, self.root / "toolchain.cmake", self.root / "out")
        self.assertEqual(code, 1)
        self.assertIn("prepared module sources missing", stderr)
        run.assert_not_called()


class TranslationTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="sun Windows translation ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for name, path in {"ROOT": self.root, "MG": self.root / "ref/ModernGekko",
                           "GAME": self.root / "game", "DESKTOP_BUILD": self.root / "tools",
                           "TRANSLATION": self.root / "build/windows-generated"}.items():
            patched = mock.patch.object(build, name, path); patched.start(); self.addCleanup(patched.stop)
        for path, data in ((build.GAME / "sys/main.dol", b"synthetic DOL\r\n"),
                           (build.DESKTOP_BUILD / "dolrecomp.exe", b"synthetic compiler"),
                           (build.ROOT / "config/dependencies.lock.json", b"{}")):
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
        self.settings = build.MG / "vendor/dolphin/Data/Sys/GameSettings/GMSE01.ini"
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text("[OnFrame]\n$Disabled patch\n0x80000000:dword:1\n")

    def compiler(self, command, env=None):
        self.assertEqual(command[:2], [build.DESKTOP_BUILD / "dolrecomp.exe", "-j2"])
        self.assertEqual(command[2:7], ["--backend=c", "--cpu", "gekko", "--gamecube", build.GAME / "sys/main.dol"])
        generated = command[-1] / "generated"
        (generated / "chunks").mkdir(parents=True)
        (generated / "generated.c").write_bytes(b"synthetic generated\r\n")
        (generated / "generated.h").write_bytes(b"synthetic header\r\n")
        (generated / "chunks/a.c").write_bytes(CORRECTED.replace("\n", "\r\n").encode())

    def translate(self):
        with mock.patch.object(build, "run", side_effect=self.compiler) as compiler, \
                mock.patch.dict(build.os.environ, {"SUNPAD_JOBS": "2"}):
            build.translate({"PATH": "synthetic environment"})
        return compiler

    def test_direct_generation_is_complete_and_reuses_only_exact_inputs_and_outputs(self):
        self.assertEqual(self.translate().call_count, 1)
        gen = build.generated_dir()
        self.assertEqual((gen / "main.dol").read_bytes(), b"synthetic DOL\r\n")
        self.assertNotIn(b"\r", (gen / "generated.c").read_bytes())
        self.assertTrue((gen / "generated_smc.txt").is_file())
        self.assertEqual(self.translate().call_count, 0)
        (gen / "chunks/a.c").write_text(CORRECTED + "changed\n")
        code, _ = exit_code(build.generated_dir); self.assertEqual(code, 1)
        self.assertEqual(self.translate().call_count, 1)
        previous = list(build.TRANSLATION.parent.glob("windows-generated.previous.*"))
        self.assertEqual(len(previous), 1)
        self.assertIn("changed", (previous[0] / "generated/chunks/a.c").read_text())

    def test_failed_regeneration_preserves_previous_and_diagnostic_outputs(self):
        self.translate()
        before = build.generated_hashes(build.TRANSLATION)
        (build.DESKTOP_BUILD / "dolrecomp.exe").write_bytes(b"new compiler")
        def fail(command, env=None):
            (command[-1] / "partial.txt").write_text("partial diagnostics")
            raise SystemExit(1)
        with mock.patch.object(build, "run", side_effect=fail):
            self.assertEqual(exit_code(build.translate, {})[0], 1)
        self.assertEqual(build.generated_hashes(build.TRANSLATION), before)
        stages = list(build.TRANSLATION.parent.glob("windows-generated.preparing.*"))
        self.assertEqual((stages[0] / "partial.txt").read_text(), "partial diagnostics")
        self.assertEqual(exit_code(build.generated_dir)[0], 1)
        self.assertEqual(self.translate().call_count, 1)
        self.assertEqual(len(list(build.TRANSLATION.parent.glob("windows-generated.previous.*"))), 1)

    def test_changed_inputs_and_added_files_invalidate_cache(self):
        self.translate()
        (build.TRANSLATION / "generated/user-notes.txt").write_text("preserve me")
        self.translate()
        previous = next(build.TRANSLATION.parent.glob("windows-generated.previous.*"))
        self.assertEqual((previous / "generated/user-notes.txt").read_text(), "preserve me")
        for path in (build.GAME / "sys/main.dol", build.ROOT / "config/dependencies.lock.json", self.settings):
            with self.subTest(path=path):
                path.write_bytes(path.read_bytes() + b"\n")
                self.assertEqual(exit_code(build.generated_dir)[0], 1)
                self.assertEqual(self.translate().call_count, 1)

    def test_enabled_default_patches_stop_before_generation(self):
        self.settings.write_text("[OnFrame_Enabled]\n $Required fix\n[OnFrame]\n$Required fix\n0x80000000:dword:1\n")
        with mock.patch.object(build, "run") as compiler:
            code, error = exit_code(build.translate, {})
        self.assertEqual(code, 1); self.assertIn("default DOL patches", error)
        compiler.assert_not_called(); self.assertFalse(build.TRANSLATION.exists())

    def test_developer_environment_cannot_change_fixed_generation_defaults(self):
        env = {"PATH": "kept tools", "DOLRECOMP_UNSAFE_DIRECT_CALLS": "1",
               "DOLRECOMP_DISPATCH_LOOKUP": "linear", "dolrecomp_c_chunk_instructions": "1"}
        with mock.patch.object(build, "run", side_effect=self.compiler) as compiler, \
                mock.patch.dict(build.os.environ, {"SUNPAD_JOBS": "2"}):
            build.translate(env)
        self.assertEqual(compiler.call_args.kwargs["env"], {"PATH": "kept tools"})
        self.assertEqual(env["DOLRECOMP_UNSAFE_DIRECT_CALLS"], "1")

    def test_inputs_changing_during_generation_are_not_published(self):
        def changing(command, env=None):
            self.compiler(command, env)
            (build.GAME / "sys/main.dol").write_bytes(b"changed during generation")
        with mock.patch.object(build, "run", side_effect=changing), \
                mock.patch.dict(build.os.environ, {"SUNPAD_JOBS": "2"}):
            code, error = exit_code(build.translate, {})
        self.assertEqual(code, 1); self.assertIn("inputs changed", error)
        self.assertFalse(build.TRANSLATION.exists())

    def test_failed_publication_restores_previous_output(self):
        self.translate()
        before = build.generated_hashes(build.TRANSLATION)
        (build.DESKTOP_BUILD / "dolrecomp.exe").write_bytes(b"changed compiler")
        rename = Path.rename
        def fail_publication(path, destination):
            if ".preparing." in path.name:
                raise PermissionError("synthetic publication failure")
            return rename(path, destination)
        with mock.patch.object(Path, "rename", fail_publication):
            with self.assertRaises(PermissionError):
                self.translate()
        self.assertEqual(build.generated_hashes(build.TRANSLATION), before)
        self.assertEqual(exit_code(build.generated_dir)[0], 1)


class UnicodeTests(unittest.TestCase):
    def test_cli_logs_unicode_command_with_utf8_disabled(self):
        fixture = r"""
import importlib.util, sys
from unittest.mock import patch
from types import SimpleNamespace
spec=importlib.util.spec_from_file_location('builder',sys.argv[1]);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with patch.object(m, 'os', SimpleNamespace(name='nt')), patch.object(sys,'argv',['build','dependencies']), patch.object(m,'dependencies',side_effect=lambda unused:m.run([sys.executable,'-c','pass','completed 雪'])):
    m.main()
"""
        result = subprocess.run([sys.executable, '-X', 'utf8=0', '-c', fixture,
                                 str(SOURCE / 'scripts/windows/build.py')],
                                env={**os.environ, 'PYTHONIOENCODING': 'cp1252'}, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', 'replace'))
        self.assertIn('completed 雪', result.stdout.decode('utf-8'))

    def test_git_metadata_path_is_decoded_as_utf8(self):
        with mock.patch.object(build.subprocess, 'check_output', return_value='metadata 雪') as command:
            self.assertEqual(build.git_lines(Path('source'), 'rev-parse', '--git-path', 'info/exclude'), 'metadata 雪')
        self.assertEqual(command.call_args.kwargs['encoding'], 'utf-8')


    @unittest.skipUnless(shutil.which('git'), 'Git is required for the metadata-path fixture')
    def test_real_git_metadata_path_survives_legacy_windows_encoding(self):
        fixture = r"""
import importlib.util, pathlib, subprocess, sys
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('builder',sys.argv[1]);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
root=pathlib.Path(sys.argv[2]);source=root/'source 雪';metadata=root/'metadata 雪'
subprocess.run(['git','init',str(source)],check=True,capture_output=True)
(source/'.git').rename(metadata)
(source/'.git').write_text('gitdir: '+metadata.as_posix()+'\n',encoding='utf-8')
with patch.object(m,'MG',source):
    m.ignore_windows_outputs()
assert '/Binary/' in (metadata/'info/exclude').read_text()
"""
        with tempfile.TemporaryDirectory(prefix='sun Git 雪 ') as temporary:
            result = subprocess.run([sys.executable, '-X', 'utf8=0', '-c', fixture,
                                     str(SOURCE / 'scripts/windows/build.py'), temporary],
                                    env={**os.environ, 'PYTHONIOENCODING':'cp1252'}, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', 'replace'))

    def test_dependency_child_uses_utf8(self):
        with mock.patch.object(build, 'run') as run:
            build.lock('--declarations-only')
        self.assertEqual(run.call_args.args[0][:3], [sys.executable, '-X', 'utf8'])

    def test_visual_studio_keeps_unicode_environment_and_uses_explicit_encodings(self):
        with tempfile.TemporaryDirectory(prefix='sun VS 雪 ') as temporary:
            programs = Path(temporary)
            installer = programs / 'Microsoft Visual Studio/Installer/vswhere.exe'
            vcvars = programs / 'VS 雪/VC/Auxiliary/Build/vcvarsarm64.bat'
            for path in (installer, vcvars):
                path.parent.mkdir(parents=True, exist_ok=True); path.touch()
            discovery = json.dumps([{'installationVersion':'17.0', 'installationPath':str(programs/'VS 雪')}])
            output = SimpleNamespace(returncode=0, stdout='Path=prepared\nINCLUDE=headers\nTEMP=temp 雪\n')
            with mock.patch.dict(build.os.environ, {'ProgramFiles(x86)':str(programs)}), mock.patch.object(build.platform,'system',return_value='Windows'), mock.patch.object(build.platform,'machine',return_value='ARM64'), mock.patch.object(build.subprocess,'check_output',return_value=discovery) as discover, mock.patch.object(build.subprocess,'run',return_value=output) as command, mock.patch.object(build.shutil,'which',return_value=str(programs/'tool.exe')), contextlib.redirect_stdout(io.StringIO()):
                result=build.visual_studio_env()
            self.assertEqual(result['TEMP'], 'temp 雪')
            self.assertIn(' /u ', command.call_args.args[0])
            self.assertEqual(command.call_args.kwargs['encoding'], 'utf-16le')
            self.assertIn('-utf8', discover.call_args.args[0])
            self.assertEqual(discover.call_args.kwargs['encoding'], 'utf-8')


if __name__ == "__main__":
    unittest.main()
