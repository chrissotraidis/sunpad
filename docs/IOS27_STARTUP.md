# iOS 27 startup compatibility

The public SunPad v0.2.0 / build 14 IPA was built with SDK 27.0, minimum iOS
16.0. Its Info.plist has no scene manifest, and its native app delegate creates
an unassociated UIWindow with the legacy application lifecycle. Apple requires
[scene lifecycle adoption](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle)
for SDK 27 apps on iOS/iPadOS 27. The lower deployment target does not exempt it.

[Issue #54](https://github.com/chrissotraidis/sunpad/issues/54) reports immediate
iPad launch failure, but supplies no model, OS version or crash report. The
scene compatibility gap is independently established by the published package
and source; the reporter's specific cause remains unconfirmed.

Current source declares one application scene and attaches the existing root
controller to its UIWindowScene. Scene events forward to the existing app
pause/resume and two-second save-flush path. Settings, save locations, game
module loading and the tvOS lane are unchanged.

The public v0.2.0 download is unchanged. SDK 27 syntax and repository/source
checks pass; full app compilation and a ROM-free scene/lifecycle probe are
pending. Physical iOS 27 startup, gameplay, audio, save/relaunch and the
reporter's acceptance remain separate gates.
