# Contributing

Use a current MoonBit toolchain and keep changes focused on the documented offline analysis boundary.

Before opening a change, run `moon fmt`, strict checks for wasm-gc/wasm/js/native, all target tests, and the native CLI demo. Add positive, negative, and boundary tests for every new modal rule or geometry case. Diagnostics should use stable codes and one-based source lines.

Do not add controller I/O, proprietary fixtures, generated build output, credentials, or unpublished competition material. Update the README, support notes, and changelog when behavior changes. Contributions are accepted under Apache-2.0.
