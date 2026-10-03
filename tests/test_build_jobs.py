"""Command fixtures only: no disc data, dependencies or compilation."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1]


class BuildJobsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sun jobs ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.scripts = self.root / "scripts"
        self.scripts.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls.jsonl"
        for name in ("prepare-game.sh", "ios-build-core-device.sh", "package-macos-app.sh"):
            shutil.copy2(SOURCE / "scripts" / name, self.scripts / name)
        self.disc = self.root / "synthetic empty input.iso"
        self.disc.touch()
        source = (self.scripts / "prepare-game.sh").read_text()
        self.disc_sha = re.search(r"EXPECTED_SHA256=([0-9a-f]+)", source).group(1)
        generated = (self.root / "ref/ModernGekko-Template/extracted/"
                     "Super-Mario-Sunshine/recomp/generated")
        generated.mkdir(parents=True)
        for name in ("generated.c", "generated.h", "main.dol"):
            (generated / name).touch()
        self.generated = generated
        self.write_tool("cmake", """#!/usr/bin/env python3
import json, os, sys
with open(os.environ['JOB_LOG'], 'a') as stream:
    stream.write(json.dumps(['cmake'] + sys.argv[1:]) + '\\n')
sys.exit(int(os.environ.get('CMAKE_BUILD_EXIT', '73')) if '--build' in sys.argv else 0)
""")
        self.write_tool("otool", """#!/usr/bin/env python3
import json, os, sys
with open(os.environ['JOB_LOG'], 'a') as stream:
    stream.write(json.dumps(['otool'] + sys.argv[1:]) + '\\n')
""")
        self.write_tool("ninja", """#!/usr/bin/env python3
import json, os, sys
with open(os.environ['JOB_LOG'], 'a') as stream:
    stream.write(json.dumps(['ninja'] + sys.argv[1:]) + '\\n')
sys.exit(0 if 'libmoderngekko.a' in sys.argv else 73)
""")
        self.write_tool("shasum", """#!/usr/bin/env python3
import json, os
with open(os.environ['JOB_LOG'], 'a') as stream:
    stream.write(json.dumps(['shasum']) + '\\n')
print(os.environ['DISC_SHA'] + '  synthetic')
""")
        for name, label in (("bootstrap-dependencies.sh", "bootstrap"),
                            ("audit-generated-gmse01.sh", "audit"),
                            ("ios-provision-device.sh", "provision")):
            path = self.scripts / name
            path.write_text("#!/usr/bin/env python3\nimport json, os, sys\n"
                            "with open(os.environ['JOB_LOG'], 'a') as stream:\n"
                            "    stream.write(json.dumps([%r] + sys.argv[1:]) + '\\n')\n"
                            "sys.exit(int(os.environ.get(%r, '0')))\n"
                            % (label, label.upper() + "_EXIT"))
            path.chmod(0o755)

    def write_tool(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def run_script(self, name, *args, **settings):
        env = os.environ.copy()
        for key in ("SUNPAD_JOBS", "CMAKE_BUILD_PARALLEL_LEVEL", "SUNPAD_CORE_ONLY",
                    "SUNPAD_IOS_MODULE_BUILD", "BASH_ENV", "BOOTSTRAP_EXIT",
                    "AUDIT_EXIT", "PROVISION_EXIT", "DISC_SHA", "CMAKE_BUILD_EXIT",
                    "SUNPAD_MACOS_BUILD_DIR", "SUNPAD_MACOS_OUTPUT"):
            env.pop(key, None)
        env.update(PATH=str(self.bin) + os.pathsep + env.get("PATH", ""),
                   JOB_LOG=str(self.log), DISC_SHA=self.disc_sha)
        env.update(settings)
        if self.log.exists():
            self.log.unlink()
        argv = ["/bin/bash", str(self.scripts / name)]
        if name == "prepare-game.sh":
            argv.append(str(self.disc))
        argv.extend(args)
        result = subprocess.run(argv, env=env, text=True, capture_output=True)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] \
            if self.log.exists() else []
        return result, calls

    def prepare_jobs(self, expected, **env):
        result, calls = self.run_script("prepare-game.sh", **env)
        self.assertEqual(result.returncode, 73, result.stderr)
        build = [call for call in calls if call[:2] == ["cmake", "--build"]]
        self.assertEqual(build, [["cmake", "--build",
                                str(self.root / "ref/ModernGekko/build-desktop-tools-public"),
                                "--target", "moderngekko-port", "moderngekko-run",
                                "-j" + expected]])
        self.assertFalse(any(call[0] in ("audit", "provision") for call in calls))

    def core_jobs(self, expected, **env):
        result, calls = self.run_script("ios-build-core-device.sh", **env)
        self.assertEqual(result.returncode, 73, result.stderr)
        ninjas = [call for call in calls if call[0] == "ninja"]
        self.assertEqual(ninjas, [
            ["ninja", "-C", str(self.root / "ref/ModernGekko/build-ios-iphoneos-public"),
             "libmoderngekko.a", "-j" + expected],
            ["ninja", "-C", str(self.root / "build/ios-module-device"), "-j" + expected]])
        self.assertTrue(any(call[0] == "audit" for call in calls))
        self.assertFalse(any(call[0] == "provision" for call in calls))

    def test_prepare_standard_limit(self):
        self.prepare_jobs("2", CMAKE_BUILD_PARALLEL_LEVEL="2")

    def test_prepare_manual_precedence(self):
        self.prepare_jobs("3", SUNPAD_JOBS="3", CMAKE_BUILD_PARALLEL_LEVEL="invalid")

    def test_prepare_default_and_empty_override(self):
        self.prepare_jobs("8")
        self.prepare_jobs("2", SUNPAD_JOBS="", CMAKE_BUILD_PARALLEL_LEVEL="2")
        self.prepare_jobs("8", SUNPAD_JOBS="", CMAKE_BUILD_PARALLEL_LEVEL="")

    def package_jobs(self, expected, **env):
        result, calls = self.run_script("package-macos-app.sh", **env)
        self.assertEqual(result.returncode, 73, result.stderr)
        build = [call for call in calls if call[:2] == ["cmake", "--build"]]
        self.assertEqual(build, [["cmake", "--build",
                                str(self.root / "ref/ModernGekko/build-desktop-app-public"),
                                "--target", "moderngekko-run", "moderngekko-launcher",
                                "-j" + expected]])

    def test_package_limits(self):
        self.package_jobs("8")
        self.package_jobs("2", CMAKE_BUILD_PARALLEL_LEVEL="2")
        self.package_jobs("4", SUNPAD_JOBS="4", CMAKE_BUILD_PARALLEL_LEVEL="invalid")

    def test_package_build_only_needs_no_game_inputs(self):
        result, calls = self.run_script("package-macos-app.sh", "--build-only",
                                       CMAKE_BUILD_EXIT="0", SUNPAD_JOBS="4")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("not a playable or releasable package", result.stdout)
        build = self.root / "ref/ModernGekko/build-desktop-app-public"
        self.assertEqual([call for call in calls if call[0] == "otool"],
                         [["otool", "-L", str(build / "SunPadFrontend")],
                          ["otool", "-L", str(build / "SunPadRunner")]])
        self.assertFalse((self.root / "build-macos").exists())

    def test_package_still_requires_the_module(self):
        result, calls = self.run_script("package-macos-app.sh", CMAKE_BUILD_EXIT="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "otool" for call in calls))
        self.assertFalse((self.root / "build-macos").exists())

    def test_package_rejects_unknown_arguments(self):
        for args in (("--release",), ("--build-only", "extra")):
            with self.subTest(args=args):
                result, calls = self.run_script("package-macos-app.sh", *args)
                self.assertEqual(result.returncode, 2)
                self.assertIn("usage:", result.stderr)
                self.assertEqual(calls, [])

    def test_core_standard_limit(self):
        self.core_jobs("2", CMAKE_BUILD_PARALLEL_LEVEL="2")

    def test_core_default_is_unchanged(self):
        self.core_jobs("8", SUNPAD_JOBS="3")
        self.core_jobs("8", CMAKE_BUILD_PARALLEL_LEVEL="")

    def test_invalid_limits_stop_before_tools(self):
        for name in ("prepare-game.sh", "ios-build-core-device.sh", "package-macos-app.sh"):
            for value in ("0", "-1", "02", "1.5", "2 3", "abc", " 2", "2\n"):
                with self.subTest(name=name, value=value):
                    result, calls = self.run_script(name, CMAKE_BUILD_PARALLEL_LEVEL=value)
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertIn("positive whole number", result.stderr)
                    self.assertEqual(calls, [])
        result, calls = self.run_script("prepare-game.sh", SUNPAD_JOBS="0",
                                       CMAKE_BUILD_PARALLEL_LEVEL="2")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(calls, [])

    def test_disc_hash_rejection_still_precedes_bootstrap(self):
        result, calls = self.run_script("prepare-game.sh", DISC_SHA="0" * 64,
                                       CMAKE_BUILD_PARALLEL_LEVEL="2")
        self.assertEqual(result.returncode, 1)
        self.assertIn("unsupported disc image", result.stderr)
        self.assertEqual(calls, [["shasum"]])

    def test_bootstrap_failure_is_fail_closed(self):
        for name in ("prepare-game.sh", "ios-build-core-device.sh", "package-macos-app.sh"):
            with self.subTest(name=name):
                result, calls = self.run_script(name, BOOTSTRAP_EXIT="23",
                                               CMAKE_BUILD_PARALLEL_LEVEL="2")
                self.assertEqual(result.returncode, 23)
                self.assertFalse(any(call[0] in ("cmake", "ninja") for call in calls))

    def test_core_only_does_not_build_a_module(self):
        result, calls = self.run_script("ios-build-core-device.sh", SUNPAD_CORE_ONLY="1",
                                       CMAKE_BUILD_PARALLEL_LEVEL="2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[-1] for call in calls if call[0] == "ninja"], ["-j2"])
        self.assertFalse(any(call[0] in ("audit", "provision") for call in calls))

    def test_missing_module_sources_still_stop(self):
        (self.generated / "generated.c").unlink()
        result, calls = self.run_script("ios-build-core-device.sh", CMAKE_BUILD_PARALLEL_LEVEL="2")
        self.assertEqual(result.returncode, 1)
        self.assertIn("prepared module sources missing", result.stderr)
        self.assertEqual(len([call for call in calls if call[0] == "ninja"]), 1)

    def test_generated_audit_failure_still_stops(self):
        result, calls = self.run_script("ios-build-core-device.sh", AUDIT_EXIT="24",
                                       CMAKE_BUILD_PARALLEL_LEVEL="2")
        self.assertEqual(result.returncode, 24)
        self.assertEqual(len([call for call in calls if call[0] == "ninja"]), 1)
        self.assertFalse(any(call[0] == "provision" for call in calls))


if __name__ == "__main__":
    unittest.main()
