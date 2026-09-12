///|
test "runtime arguments preserve unknown commands and command-like filenames" {
  assert_eq(cli_arguments(["node", "main.js", "auidt", "audit"], 2), [
    "auidt", "audit",
  ])
  assert_eq(cli_arguments(["main", "auidt", "audit"], 1), ["auidt", "audit"])
  assert_eq(cli_arguments(["main.wasm", "analyze", "demo"], 1), [
    "analyze", "demo",
  ])
}

///|
test "no user arguments selects the explicit built-in demo" {
  assert_eq(cli_arguments(["node", "main.js"], 2), ["demo"])
  assert_eq(cli_arguments(["main"], 1), ["demo"])
}
