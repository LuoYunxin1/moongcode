# MoonGCode

MoonGCode is an offline MoonBit library and CLI for explaining, replaying, and safety-checking a bounded CNC/laser/plotter G-code program. It resolves modal state into millimetre toolpath segments, computes deterministic geometry and time estimates, and checks a machine envelope before a program is sent to hardware.

The project is intentionally an analysis tool. It never opens a serial port, controls a machine, replaces a CAM post-processor, or claims that a passing static audit makes a physical setup safe.

## Quick start

Install the MoonBit toolchain, then run the built-in acceptance example:

```text
moon run cmd/main -- demo
```

Analyze a file with the same commands:

```text
moon run cmd/main -- validate examples/safe.nc
moon run cmd/main -- normalize examples/safe.nc
moon run cmd/main -- trace examples/safe.nc
moon run cmd/main -- analyze examples/safe.nc
moon run cmd/main -- audit examples/safe.nc
moon run cmd/main -- audit-laser examples/laser.nc
moon run cmd/main -- audit-profile examples/safe.nc examples/desktop-mill.profile
moon run cmd/main -- audit-md examples/safe.nc
moon run cmd/main -- explain examples/safe.nc
```

`audit` uses the deterministic `desktop-mill` profile. Applications can parse and construct their own `MachineProfile` values through the library API.
The fixtures also include `examples/inches.nc` to demonstrate deterministic inch-to-millimetre conversion.

## Library workflow

```moonbit
let execution = @moongcode.interpret_source(source)
let stats = @moongcode.analyze_execution(execution)
let report = @moongcode.audit_execution(execution, @moongcode.MachineProfile::desktop_mill())
println(@moongcode.safety_report_text(report))
```

The supported core is deliberately bounded: `G0/G1/G2/G3`, `G4`, `G17/G18/G19`, `G20/G21`, `G90/G91`, `G90.1/G91.1`, `F/S/T`, `M0/M1/M2/M3/M4/M5/M30`, XYZ/IJK/R/P parameters, semicolon and parenthesized comments, and optional line checksums. Unsupported commands are stable errors by default and can be downgraded to warnings only when the caller explicitly opts in.

The parser preserves source lines and diagnostics. The interpreter returns modal snapshots and immutable `Segment` values. Geometry handles line distance, plane projection, IJK center offsets, signed R arcs, helical arcs, bounds, and unit conversion. The audit layer checks workspace bounds, feed and spindle limits, spindle state, rapid Z descent, arc radius, dwell duration, tool allowlists, and program termination.

## Verification

```text
moon fmt --check
moon check --target wasm-gc --deny-warn
moon check --target wasm --deny-warn
moon check --target js --deny-warn
moon check --target native --deny-warn
moon test --target wasm-gc
moon test --target wasm
moon test --target js
moon test --target native
moon build cmd/main --target native --release
```

The test suite includes positive, malformed, boundary, modal-conflict, geometry, and safety cases. GitHub Actions repeats portable and native checks on a clean runner.

## Project boundaries and originality

MoonGCode is an original MoonBit implementation for physical-machine program preflight. It is not a port and has no runtime dependency on a controller or CAD system. A registry comparison and MoonCakes/GitHub search were completed before implementation; no comparable MoonBit G-code/CNC/toolpath project was found. Shared practices such as parsing, diagnostics, tests, and CI are not the project identity.

## License and responsible use

Source code is Apache-2.0. The only runtime dependency is `moonbitlang/x`, used for standard filesystem and process helpers in the example CLI. See `THIRD_PARTY.md`, `SECURITY.md`, and `AI_USAGE.md` for attribution, reporting, and development-assistance details.
