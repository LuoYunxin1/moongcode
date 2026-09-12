# Independent reference checks

Run from any directory: `python scripts/verify_reference.py` (Python 3 standard
library, MoonBit, Node.js). The script builds the release CLI and invokes it in
fresh processes. `--target native` requires a C compiler. `--output result.json`
saves measured evidence; `--repo /path/to/baseline` checks a separate checkout
without changing the current branch. A mismatch exits 1; build/runtime errors
also fail the run. JSON includes the tested Git revision, oracle SHA-256 and
runtime versions. Run against a committed, unmodified source tree for attribution.

- **432 arc fixtures**: 3 planes × 2 directions × 2 unit systems × 2 center
  modes × 3 radii × 3 rises × 2 sweeps. Source radii: 0.25, 1, 10; rise/radius:
  -2, 0, 3; sweeps: quarter and full circle. All use IJK, absolute endpoints and
  F60. Arc distance is isolated from CLI total distance by subtracting the known
  initial rapid distance. Reference length is `hypot(radius * angle, rise)`;
  time includes the initial rapid at 6000 mm/min and arc feed converted to mm/min.
- **24 workspace fixtures**: 3 planes × 2 directions × same/separate plane block
  × inside/outside limit. A radius-5 full circle has endpoints inside both
  profiles but an extremum outside the ±4 profile; the ±6 profile must pass.
  The oracle checks both exit status and the workspace diagnostic, preventing
  unrelated errors from satisfying the expected failure.
- **14 CLI contracts**: positional dispatch, argument count, missing input,
  parse/replay failures, syntax-only validation and help/default behavior.

Numeric tolerance: absolute 1e-9 OR relative 1e-12 (`math.isclose`). Non-finite
results fail. Reported maxima cover every parsed finite numeric result, including
failed baseline cases. Only the first four failures per group are retained.
These are constructed correctness checks, **not** throughput benchmarks, random
fuzzing, controller-equivalence tests, or evidence of physical-machine safety.
R-format arcs and arbitrary sweeps remain covered by the ordinary geometry tests,
not by this analytic grid. The oracle must not be changed merely to accept a
regression. CI runs it independently on JavaScript and native builds.
