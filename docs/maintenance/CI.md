# Maintenance CI status

As of 2026-09-12, the maintenance branch has not yet been confirmed by a completed
remote CI run. Do not treat the historical baseline's green CI as verification
of the maintenance changes.

Local evidence: formatting and four strict target checks pass; wasm-gc/wasm/JS
have 104 passing tests each. The JavaScript reference runner passes 470/470
constructed checks. Native execution is unverified locally because no C compiler
is available. This file will be updated with the actual remote run and artifacts.
