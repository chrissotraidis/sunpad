# Engine memory probe

Task E1.1 of the [decompilation engine plan](../../docs/DECOMP-ENGINE-PLAN.md).
A separate app (`com.sunpad.engineprobe`) that checks the address windows the
decompiled engine needs. It never touches SunPad's bundle or data.

```sh
scripts/engine-memory-probe/build.sh iphonesimulator build/engine-probe
scripts/engine-memory-probe/build.sh iphoneos build/engine-probe "Apple Development: NAME" path/to/profile.mobileprovision
```

Each launch writes `Documents/engine-memory-probe-<time>.json` and logs the
same report with the prefix `SUNPAD_ENGINE_PROBE`.
