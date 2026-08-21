///|
fn render_test_block() -> Block {
  Block::new(
    4,
    Some(7),
    [
      Word::new('X', 2.0, "x2", 10),
      Word::new('G', 1.0, "g1", 6),
      Word::new('M', 3.0, "m3", 2),
    ],
    Some("finish"),
    Some(11),
    "N7 X2 G1 M3 (finish)*11",
  )
}

///|
test "normalize block orders addresses" {
  assert_eq(normalize_block(render_test_block()), "N7 G1 M3 X2 *11")
}

///|
test "normalize block optionally keeps comments" {
  let block = render_test_block()
  assert_true(!normalize_block(block).contains("finish"))
  assert_true(normalize_block(block, preserve_comment=true).contains(";finish"))
}

///|
test "normalize block keeps sequence first" {
  let block = Block::new(
    1,
    Some(12),
    [Word::new('X', 1.0, "X1", 4)],
    None,
    None,
    "N12 X1",
  )
  assert_eq(normalize_block(block), "N12 X1")
}

///|
test "normalize block formats G and M integers" {
  let block = Block::new(
    1,
    None,
    [Word::new('M', 3.0, "M3.0", 1), Word::new('G', 1.0, "G1.0", 5)],
    None,
    None,
    "M3.0 G1.0",
  )
  assert_eq(normalize_block(block), "G1 M3")
}

///|
test "normalize block folds negative zero" {
  let block = Block::new(
    1,
    None,
    [Word::new('X', -0.0, "X-0", 1), Word::new('Y', -2.5, "Y-2.5", 5)],
    None,
    None,
    "X-0 Y-2.5",
  )
  assert_eq(normalize_block(block), "X0 Y-2.5")
}

///|
test "normalize block keeps repeated words by source order" {
  let block = Block::new(
    1,
    None,
    [
      Word::new('X', 3.0, "X3", 9),
      Word::new('X', 1.0, "X1", 2),
      Word::new('X', 2.0, "X2", 5),
    ],
    None,
    None,
    "X3 X1 X2",
  )
  assert_eq(normalize_block(block), "X1 X2 X3")
}

///|
test "normalize block has explicit checksum retention" {
  let block = render_test_block()
  assert_true(normalize_block(block).has_suffix("*11"))
}

///|
test "validate report marks valid program" {
  let report = validate_report(parse_program("G1 X2"))
  assert_true(report.has_prefix("VALID\nblocks: 1"))
  assert_true(!report.contains("diagnostics:"))
}

///|
test "validate report includes stable diagnostics" {
  let report = validate_report(parse_program("G X1"))
  assert_true(report.has_prefix("INVALID\nblocks: 1"))
  assert_true(report.contains("parse.word.missing_value"))
  assert_true(report.contains("line 1:"))
}

///|
test "explain block includes normalized text" {
  let explanation = explain_block(render_test_block())
  assert_true(explanation.has_prefix("line 4 sequence=7 words=3"))
  assert_true(explanation.contains("| N7 G1 M3 X2 *11"))
}

///|
test "explain line returns selected block" {
  let result = explain_line("G0\nG1 X2", line_number=2)
  assert_eq(result, Ok("line 2 words=2 | G1 X2"))
}

///|
test "explain line isolates diagnostics by line" {
  let result = explain_line("G\nG1 X2", line_number=2)
  assert_eq(result, Ok("line 2 words=2 | G1 X2"))
}

///|
test "explain line returns parse diagnostics" {
  let result = explain_line("G X1")
  match result {
    Ok(_) => fail("expected a diagnostic result")
    Err(diagnostics) =>
      assert_true(
        diagnostics.any(fn(item) { item.code() == "parse.word.missing_value" }),
      )
  }
}

///|
test "execution trace reports units mode positions and diagnostics" {
  let trace = execution_trace_text(interpret_source("G20 G91 F1\nG1 X1\n"))
  assert_true(trace.has_prefix("TRACE\nline 1"))
  assert_true(trace.contains("units=inch"))
  assert_true(trace.contains("(0,0,0) -> (25.4,0,0)"))
}

///|
test "trace line explanation selects executed transition" {
  let execution = interpret_source("G21 F60 M3 S500\nG1 X2\nM5 M30\n")
  let explanation = explain_trace_line(execution, 2).unwrap()
  assert_true(explanation.contains("position (0,0,0) -> (2,0,0)"))
  assert_true(explanation.contains("motion=G1 feed=60 spindle=clockwise"))
  assert_true(explain_trace_line(execution, 99) is Err(_))
}

///|
test "explain line rejects blank lines" {
  let result = explain_line("\nG1", line_number=1)
  match result {
    Ok(_) => fail("expected an empty-line diagnostic")
    Err(diagnostics) => assert_eq(diagnostics[0].code(), "render.line.empty")
  }
}

///|
test "explain line rejects invalid line numbers" {
  let result = explain_line("G1", line_number=0)
  match result {
    Ok(_) => fail("expected a range diagnostic")
    Err(diagnostics) => assert_eq(diagnostics[0].code(), "render.line.range")
  }
}

///|
test "explain program is source ordered" {
  let program = parse_program("M3\nG1 X1")
  assert_eq(
    explain_program(program),
    "line 1 words=1 | M3\nline 2 words=2 | G1 X1",
  )
}
