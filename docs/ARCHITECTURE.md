# Architecture

The project is a pure data pipeline:

1. `text.mbt` and `parser.mbt` turn physical lines into `Program`, `Block`, and `Word` values without throwing.
2. `interpreter.mbt` applies modal groups to an immutable `MachineState` snapshot and emits `TraceStep` and `Segment` values.
3. `geometry.mbt` resolves unit-aware points and circular/helical geometry in XY, ZX, or YZ planes.
4. `audit.mbt` aggregates the replay and evaluates it against `MachineProfile` limits.
5. `cmd/main` exposes the same pipeline as deterministic text commands.

The library has no hardware, network, clock, or filesystem dependency. The CLI filesystem boundary is limited to reading the explicitly supplied source file.
