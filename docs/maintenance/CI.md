# Verified maintenance CI

Verified on 2026-09-12. Source commit: `bfdf650b55ef026f276ad99a4cfa59347bd37f89`.
GitHub Actions run **34702797535** completed successfully; both portable and native jobs passed.
Run: https://github.com/LuoYunxin1/moongcode/actions/runs/34702797535

| Gate | Actual result |
|---|---|
| Format / strict checks | Format plus wasm-gc, wasm, JS and native strict checks passed |
| Ordinary tests | 104/104 on each of wasm-gc, wasm, JS and native |
| Native CLI | Compiled release binary and demo acceptance passed |
| JS reference oracle | 432 arcs + 24 workspace checks + 14 CLI contracts, all passed |
| Native reference oracle | 432 arcs + 24 workspace checks + 14 CLI contracts, all passed |

Toolchain: moon 0.1.20260904; moonc v0.10.12+1634b282e (2026-09-07).
Downloaded artifacts have been archived here so that evidence remains available
after GitHub artifact expiration. These files are measured outputs, not manually
recreated result summaries. Both report the tested source SHA and oracle hash.

- `ci-js.json` SHA-256: `c7350ea94384220470ba0dcd936cece57bc27ab9f019fc31cb36558292ec7154`
- `ci-native.json` SHA-256: `20ad216bfee167503b57803ae8a3c693f9474a0fe65bbdc5dbeff054ecc9f556`

The earlier run **34702065465**, at `568bb30`, failed on current formatter rules
and two deprecated `StringBuilder::new()` calls. Commit `bfdf650` fixed these
without removing `--deny-warn` or the format gate. The successful run above is
the actual rerun, not an inference from the historical baseline.

Native execution was performed on the Linux CI runner, not on the Windows host
(which has no C compiler). The isolated Windows v0.10.12 installation separately
passed formatting, four strict checks, three targets of 104 tests and the same
470 JavaScript reference checks. The global toolchain and user PATH were unchanged.

The evidence-publication commit following this run changes documentation and
archived JSON only; check the Actions tab for the result of any later code change.
