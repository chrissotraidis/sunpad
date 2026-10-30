# SunPad 0.2.3 — reject incomplete game-data imports

Version 0.2.3, build 17, fixes an extraction failure that could replace a working
installation with incomplete game files. The underlying directory exporter logs
individual read/write failures and continues. A truncated file still exists, so
the previous existence and file-count checks could accept it.

SunPad now checks every extracted game file's type and exact length against the
verified disc's file table before reporting success. An incomplete extraction
returns an error through the existing staging cleanup path, before the running
game is stopped or installed data is replaced. The supported disc, picker,
controls and save paths are unchanged.

## Validation

The focused extraction test reproduces the old false success with a short final
write. The corrected production extractor passes complete output, truncated
output with an unchanged file count, missing output, and a directory substituted
for a file. Nested directories and a valid zero-byte file are covered. The
delayed progress-callback regression remains included; the test uses ASan and
UBSan with synthetic files and a controlled DiscIO exporter.

The release uses the existing PadMint route: a game-code-free unsigned app shell,
recipe and checksums. PadMint translates the player's own supported disc into a
private module and adds it to that shell. A private completed app or game-derived
module must never be published. Source checks, builds, public-artifact gates and
clean pre/post-publication PadMint checks are recorded with the release evidence.

Synthetic failure tests and package builds do not establish physical gameplay
or the behavior of a particular Files provider. No player issue is closed by
this change without the corresponding device confirmation.
