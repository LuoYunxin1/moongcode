# Local readiness audit

Date: 2026-08-21

- Real Git commits: `939940c` domain model, `2c2c21f` parser/profile/text/geometry, `7cf89b6` interpreter/audit/render/CLI.
- `moon fmt --check`: passed.
- `moon check --target wasm-gc --deny-warn`: passed.
- `moon check --target wasm --deny-warn`: passed.
- `moon check --target js --deny-warn`: passed.
- `moon check --target native --deny-warn`: passed at type-check stage.
- `moon test --target wasm-gc`: 90 passed.
- `moon test --target wasm`: 90 passed.
- `moon test --target js`: 90 passed.
- Native tests/build: deferred to GitHub Actions because this Windows host has no C compiler (`cl`, `cc`, `gcc`, and `clang` unavailable).
- CLI demo, safe fixture audit, unsafe fixture rejection, normalization, trace, and statistics: passed locally.
- Submission draft: `C:\Users\42673\Desktop\工作区\随用随清\moongcode-application.md`, strict validator passed.
- GitHub repository: public `https://github.com/LuoYunxin1/moongcode`, default branch `main`.
- GitHub Actions: portable and native jobs passed at the initial delivery commit; the documentation-only delivery audit is rechecked by CI.
- Release: `v0.1.0` was published from the initial tested commit; the final audit update is released as `v0.1.1`.
