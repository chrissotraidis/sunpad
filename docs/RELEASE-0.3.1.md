# SunPad 0.3.1 — Windows builds without a Python install

Version 0.3.1, build 19, fixes the experimental Windows build route from 0.3.0.
On a PC without its own Python installation, which is most Windows PCs, the
build stopped at the start of the iPhone module stage:
`Could NOT find Python3 (missing: Python3_EXECUTABLE Interpreter)` at
`CMakeLists.txt:40`, then `cmake failed (exit 1)`.

Dolphin's module template runs a small Python script, and
`scripts/windows/build.py` let CMake search the system for Python. Both CMake
configure steps now use the Python that runs the builder, which on a player's PC
is the one PadMint for Windows brings. The 0.3.0 proof missed this because its
test VM also had Python installed system-wide.

Macs and Linux are unchanged, and so is the app.

## Validation

- Windows 11 ARM64 VM with its system Python hidden, PadMint 0.6.4 for
  Windows and a fresh PadMint folder: the published 0.3.0 failed with the
  player's exact error; the fixed source then built the personal IPA.
- The Windows builder tests now check that the module configure names this
  Python. CI passes, including the native x64 Windows route.
