import json
import plistlib
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class TvOSContractTests(unittest.TestCase):
    def text(self, path):
        return (ROOT / path).read_text()

    def png_header(self, path):
        data = (ROOT / path).read_bytes()
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(data[12:16], b"IHDR")
        return struct.unpack(">IIBBBBB", data[16:29])

    def test_target_and_metadata_are_project_owned(self):
        project = self.text("SunPad.xcodeproj/project.pbxproj")
        self.assertIn("name = SunPadTV;", project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = com.sunpad.SunPad.tv;", project)
        self.assertIn("TVOS_DEPLOYMENT_TARGET = 17.0;", project)
        self.assertIn("gGMSE01_recomp.dylib in Copy Module", project)
        with (ROOT / "apple/tvos/Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
        self.assertIn("TARGETED_DEVICE_FAMILY = 3;", project)
        self.assertTrue(info["GCSupportsControllerUserInteraction"])
        self.assertEqual(
            info["GCSupportedGameControllers"], [{"ProfileName": "ExtendedGamepad"}]
        )

    def test_runtime_is_narrow_and_fail_closed(self):
        host = self.text("apple/tvos/SunPadTVAppDelegate.mm")
        self.assertIn("NSCachesDirectory", host)
        self.assertNotIn("NSApplicationSupportDirectory", host)
        self.assertIn('stringByAppendingPathComponent:@"GameData/GMSE01"', host)
        self.assertIn('stringByAppendingPathComponent:@"gGMSE01_recomp.dylib"', host)
        self.assertIn("13934c863d649b1ddca1ca4d7748f49d28a571685cbee5fb1542545c32869955", host)
        self.assertIn("settings.renderScale = 1", host)
        self.assertIn("settings.aspectRatioMode = SunPadAspectRatioOriginal", host)
        self.assertIn("settings.experimental60FPS = NO", host)
        self.assertIn("settings.experimentalPerformanceMode = NO", host)
        self.assertIn("SunPadInputMixer.sharedMixer", host)
        self.assertIn("GCControllerDidConnectNotification", host)
        self.assertIn("GCControllerDidDisconnectNotification", host)
        self.assertNotIn("UIDocumentPicker", host)

    def test_build_produces_core_and_tvos_module(self):
        build = self.text("scripts/tvos-build-core-device.sh")
        toolchain = self.text("scripts/tvos-device-toolchain.cmake")
        provision = self.text("scripts/tvos-provision-device.sh")
        self.assertIn("set(CMAKE_SYSTEM_NAME tvOS)", toolchain)
        self.assertIn("module-template", build)
        self.assertIn("-DCMAKE_SYSTEM_NAME=tvOS", build)
        self.assertIn("gGMSE01_recomp.dylib", provision)
        self.assertNotIn("Xcode-27", build + provision)
        self.assertIn("platform +TVOS", provision)

    def test_device_workflow_preserves_scope(self):
        stage = self.text("scripts/stage-tvos-game-data.sh")
        backup = self.text("scripts/backup-tvos-state.sh")
        diagnostics = self.text("scripts/collect-tvos-diagnostics.sh")
        self.assertIn('"$STAGING/SunPad/GameData/GMSE01"', stage)
        self.assertIn('--destination "Library/Caches"', stage)
        self.assertIn("13934c863d649b1ddca1ca4d7748f49", stage)
        self.assertIn("appDataContainer", stage)
        self.assertIn("--remove-existing-content false", stage)
        self.assertIn("Config GC", backup)
        self.assertNotIn("GameData", backup)
        self.assertIn("Library/Caches/SunPad/Logs", diagnostics)
        self.assertIn("<app-container>", diagnostics)

    def test_layered_assets_have_expected_dimensions(self):
        base = Path("apple/tvos/Assets.xcassets/App Icon.brandassets")
        expected = {
            base / "Top Shelf Image.imageset/top-shelf.png": (1920, 720),
            base / "App Icon - Large.imagestack/Background.imagestacklayer/Content.imageset/background-large.png": (1280, 768),
            base / "App Icon - Large.imagestack/Mark.imagestacklayer/Content.imageset/mark-large.png": (1280, 768),
            base / "App Icon - Small.imagestack/Background.imagestacklayer/Content.imageset/background.png": (400, 240),
            base / "App Icon - Small.imagestack/Mark.imagestacklayer/Content.imageset/mark@2x.png": (800, 480),
        }
        for path, dimensions in expected.items():
            self.assertEqual(self.png_header(path)[:2], dimensions)
        for manifest in (ROOT / "apple/tvos/Assets.xcassets").rglob("Contents.json"):
            json.loads(manifest.read_text())

    def test_package_audits_both_macho_files(self):
        app_audit = self.text("scripts/audit-tvos-app.sh")
        package = self.text("scripts/package-tvos.sh")
        package_audit = self.text("scripts/audit-tvos-package.sh")
        self.assertIn("for binary in", app_audit)
        self.assertIn("platform +TVOS", app_audit)
        self.assertIn("gGMSE01_recomp.dylib", app_audit + package + package_audit)
        self.assertIn("INSTALL_TVOS.md", package + package_audit)
        self.assertIn("_CodeSignature", package_audit)


if __name__ == "__main__":
    unittest.main()
