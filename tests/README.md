# Tests

Focused source tests for the app's shared code. Each `test-*.sh` compiles
one test against the sources in `apple/` and runs it. `scripts/check-repository.sh`
runs all of them with the repository checks:

```sh
./scripts/check-repository.sh
```

[docs/TESTING.md](../docs/TESTING.md) describes what each test covers, the
builds, package audits and routes, the device evidence, and the hands-on
checklist. A test that passes is source evidence only: gameplay needs a route
or hands-on play on a device.
