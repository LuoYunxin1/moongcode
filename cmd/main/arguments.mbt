///|
// Node includes both its executable and script path; other runtimes include
// only the program path. Never scan user arguments for a known command.
#cfg(target="js")
fn runtime_argument_prefix() -> Int {
  2
}

///|
#cfg(not(target="js"))
fn runtime_argument_prefix() -> Int {
  1
}

///|
fn cli_arguments(raw : Array[String], prefix : Int) -> Array[String] {
  if raw.length() <= prefix {
    ["demo"]
  } else {
    raw[prefix:].to_owned()
  }
}
