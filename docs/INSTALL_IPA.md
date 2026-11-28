# Install your personal SunPad IPA

> [!IMPORTANT]
> **The published app has no game engine.** Follow the README's
> [Get SunPad](https://github.com/chrissotraidis/sunpad#get-sunpad) steps on an
> Apple silicon Mac with Xcode and Homebrew. PadMint compiles the engine from
> the decompilation's public source and adds it to the published app. Keep the
> resulting personal IPA to yourself: it contains the compiled game code.

Use the unsigned arm64 IPA PadMint saved in Downloads, on an iPhone or iPad
running iOS or iPadOS 16 or later.

1. Use the personal IPA PadMint made. The published IPA alone opens to a
   message asking for a PadMint copy.
2. Sign and install it with a sideloading tool you trust (AltStore Classic,
   SideStore or Sideloadly), making sure the nested
   `Frameworks/libsms_embed.dylib` is signed with the app.
3. Open SunPad. On first launch, choose **Choose ISO or GCM** and select your
   own Super Mario Sunshine USA revision 0 (`GMSE01`) ISO or GCM image. To
   replace it later, use **••• → Game Data → Import or Reimport Game Data**.

If choosing the image through a Files provider doesn't work, put it in
**Files → On My iPhone/iPad → SunPad**, then choose **••• → Game Data →
Import from SunPad Folder**. SunPad checks the image's SHA-256 and keeps a
private copy, which the engine reads directly. Delete the dropped file
yourself after the game starts if you want the space back.

The personal IPA contains SunPad's app, MoltenVK and the engine compiled on
your Mac. It contains no disc image, extracted game files, save, settings,
certificate or provisioning profile. It isn't an App Store, TestFlight or
computer-free release.

## Updating from 0.3.x

Install 0.4.0 over the existing SunPad with the same bundle identifier
(`com.sunpad.SunPad`) and signing setup. On first launch:

- your 0.3.x saves are copied to the new engine's memory card. The 0.3.x save
  files stay as they were, so going back to 0.3.x finds them unchanged
  (without progress made on 0.4.0).
- your touch layout, controller mapping and settings carry over.
- the disc image you imported is used as it is. The extracted copy 0.3.x also
  kept (about 1.4 GB) stays until you reimport or choose **Remove Stored Game
  Data**.

Export your saves first anyway (**••• → Saves → Export Saves…**). Uninstalling
removes SunPad's data and saves, and a different bundle identifier or team
installs a separate app with none of them.

## Old previews

Preview IPAs and 0.3.x copies used the legacy engine and its
`gGMSE01_recomp.dylib` module. See the
[legacy engine record](LEGACY-ENGINE.md) and the
[0.3.x install guide](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/INSTALL_IPA.md).

## LiveContainer status

LiveContainer isn't a supported or verified install path, and SunPad 0.4.0
hasn't been tried in it. The engine is a library in `Frameworks`, which
LiveContainer signs with the rest of the guest app, and SunPad finds it
through `NSBundle.mainBundle`, which LiveContainer redirects to the guest
app. Neither has been checked in practice.

To report a LiveContainer failure, include the IPA's SHA-256, LiveContainer's
version and source, the device and OS version, the signing and JIT settings,
the first visible error, LiveContainer's launch output, and whether the same
IPA works when installed normally. Never attach the game image, extracted
game files, saves, signing material or a device container.
