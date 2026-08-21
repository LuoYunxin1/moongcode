///|
test "initial machine state is deterministic" {
  let state = MachineState::initial()
  assert_eq(state.position(), Point3::origin())
  assert_eq(state.units(), Millimeters)
  assert_eq(state.distance_mode(), Absolute)
  assert_eq(state.motion(), NoMotion)
  assert_eq(state.spindle(), SpindleOff)
}

///|
test "block lookup preserves repeated values" {
  let block = Block::new(
    4,
    Some(10),
    [Word::new('G', 1.0, "G1", 1), Word::new('X', 2.5, "X2.5", 4)],
    None,
    None,
    "N10 G1 X2.5",
  )
  assert_eq(block.first_value('X'), Some(2.5))
  assert_eq(block.values('G'), [1.0])
}

///|
test "diagnostic text is stable" {
  let item = Diagnostic::error("parse.word", 3, 7, "missing numeric value")
  assert_eq(item.to_text(), "error[parse.word] line 3:7 missing numeric value")
}

///|
test "diagnostic queries preserve severity and code" {
  let values = [
    Diagnostic::error("same", 1, 1, "first"),
    Diagnostic::warning("same", 2, 1, "second"),
    Diagnostic::info("other", 3, 1, "third"),
  ]
  assert_eq(diagnostics_by_severity(values, Warning).length(), 1)
  assert_eq(diagnostics_count_code(values, "same"), 2)
  assert_eq(diagnostics_summary(values), "errors=1 warnings=1 info=1")
}
