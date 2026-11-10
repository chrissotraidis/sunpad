# tvOS asset provenance

Updated on 2026-10-26 from SunPad's selected illustrated island-and-sun icon,
`apple/ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. See the
[master provenance](../../ios/Assets.xcassets/AppIcon.appiconset/PROVENANCE.md).

- Background layers: opaque ocean blue (sRGB 0.025, 0.24, 0.70).
- Middle layers: empty transparent spacing layers for the parallax stack.
- Foreground layers: the complete square icon, centered without cropping at
  86% of the canvas height. Canvas sizes remain 400×240, 800×480 and 1280×768.
- Top Shelf: the complete icon at 620×620, centered on a 1920×720 blue canvas.
- `SunPadBrand.imageset`: 256×256 artwork for the in-app setup screen.

The canvas exports use macOS Core Graphics; the square resize uses `sips`.
No game image, extracted game asset, save, or official banner artwork was used.
