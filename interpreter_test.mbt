///|
fn demo_program() -> String {
  "G21 G90 F600\n" +
  "T1 M3 S12000\n" +
  "G0 X10 Y10 Z5\n" +
  "G1 Z0\n" +
  "G1 X30 Y10\n" +
  "G2 X10 Y10 I-10 J0\n" +
  "M5 M30\n"
}

///|
test "executes modal linear and arc moves" {
  let execution = interpret_source(demo_program())
  assert_true(execution.segments().length() >= 4)
  assert_eq(execution.final_state().position(), Point3::new(10.0, 10.0, 0.0))
  assert_eq(execution.final_state().spindle(), SpindleOff)
  assert_eq(execution.final_state().status(), Ended)
  assert_true(execution.is_valid())
}

///|
test "converts inches and incremental coordinates" {
  let execution = interpret_source("G20 G91 F1\nG1 X1 Y2\n")
  assert_eq(execution.final_state().position(), Point3::new(25.4, 50.8, 0.0))
  assert_eq(execution.final_state().units(), Inches)
  assert_eq(execution.final_state().feed_mm_min(), 25.4)
}

///|
test "modal motion persists to following block" {
  let execution = interpret_source("G21 F100\nG1 X1\nX2\n")
  assert_eq(execution.segments().length(), 2)
  assert_eq(execution.final_state().position().x(), 2.0)
}

///|
test "supports radius arcs and non-XY planes" {
  let execution = interpret_source("G21 G90 F100\nG18 G2 X0 Z10 R5\n")
  assert_true(execution.segments().length() == 1)
  assert_eq(execution.segments()[0].kind(), ClockwiseArcSegment)
  assert_eq(execution.final_state().position(), Point3::new(0.0, 0.0, 10.0))
}

///|
test "supports dwell and pause" {
  let execution = interpret_source("G4 P2\nM0\nG1 X1 F10\n")
  assert_eq(execution.segments()[0].kind(), DwellSegment)
  assert_eq(execution.segments()[0].duration_seconds(), 2.0)
  assert_eq(execution.final_state().status(), Ready)
}

///|
test "reports missing feed and unsupported commands" {
  let execution = interpret_source("G1 X4\nG99\n")
  assert_false(execution.is_valid())
  assert_true(
    execution
    .diagnostics()
    .any(fn(item) { item.code() == "interpret.feed.missing" }),
  )
  assert_true(
    execution
    .diagnostics()
    .any(fn(item) { item.code() == "interpret.unsupported_g" }),
  )
}

///|
test "allows explicitly configured unsupported commands as warnings" {
  let execution = interpret_source("G99\n", allow_unsupported=true)
  assert_true(execution.is_valid())
  assert_true(
    execution.diagnostics().any(fn(item) { item.severity() == Warning }),
  )
}

///|
test "rejects duplicate modal and arc parameters" {
  let execution = interpret_source("G0 G1 X1 F10 F20\nG2 X0 R2 I1\n")
  assert_true(
    execution
    .diagnostics()
    .any(fn(item) { item.code() == "interpret.modal_conflict" }),
  )
  assert_true(
    execution
    .diagnostics()
    .any(fn(item) { item.code() == "interpret.duplicate_word" }),
  )
  assert_true(
    execution
    .diagnostics()
    .any(fn(item) { item.code() == "interpret.arc.conflict" }),
  )
}

///|
test "rejects orphan axis and invalid dwell" {
  let execution = interpret_source("X1\nG4\nG4 P-1\n")
  assert_true(
    execution
    .diagnostics()
    .any(fn(item) { item.code() == "interpret.motion.missing" }),
  )
  assert_true(
    execution
    .diagnostics()
    .any(fn(item) { item.code() == "interpret.dwell.missing" }),
  )
  assert_true(
    execution
    .diagnostics()
    .any(fn(item) { item.code() == "interpret.dwell.invalid" }),
  )
}

///|
test "supports absolute arc centers" {
  let execution = interpret_source(
    "G21 G90 G90.1 F100\nG1 X10 Y0\nG2 X0 Y0 I5 J0\n",
  )
  assert_true(execution.segments().length() == 2)
  assert_eq(execution.final_state().position(), Point3::origin())
}

///|
test "rejects motion after program end" {
  let execution = interpret_source("M30\nG1 X1 F10\n")
  assert_true(
    execution
    .diagnostics()
    .any(fn(item) { item.code() == "interpret.after_end" }),
  )
  assert_eq(execution.final_state().status(), Ended)
}
