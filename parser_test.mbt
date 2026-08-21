///|
fn parser_has_code(program : Program, code : String) -> Bool {
  program.diagnostics().any(fn(item) { item.code() == code })
}

///|
fn parser_first(program : Program) -> Block {
  program.blocks()[0]
}

///|
test "parser accepts compact and spaced words" {
  let program = parse_program("g1x1.5 Y-2 z.25")
  assert_true(program.is_valid())
  let block = parser_first(program)
  assert_eq(block.words().length(), 4)
  assert_eq(block.words()[0].letter(), 'G')
  assert_eq(block.words()[1].value(), 1.5)
  assert_eq(block.words()[2].value(), -2.0)
  assert_eq(block.words()[3].value(), 0.25)
}

///|
test "parser preserves sequence separately" {
  let program = parse_program("N010 G01 X2")
  assert_true(program.is_valid())
  let block = parser_first(program)
  assert_eq(block.sequence(), Some(10))
  assert_eq(block.words().map(fn(word) { word.letter() }), ['G', 'X'])
}

///|
test "parser accepts CRLF and percent sentinels" {
  let program = parse_program("%\r\nG0 X0\r\n%\r\n")
  assert_true(program.is_valid())
  assert_eq(program.blocks().length(), 1)
  assert_eq(program.blocks()[0].source_line(), 2)
}

///|
test "parser keeps parenthesis and semicolon comments" {
  let program = parse_program("G1 X1 (rough pass) Y2 ; final pass")
  assert_true(program.is_valid())
  assert_eq(parser_first(program).comment(), Some("rough pass final pass"))
  assert_eq(parser_first(program).words().length(), 3)
}

///|
test "parser emits comment-only block" {
  let program = parse_program("(setup only)")
  assert_true(program.is_valid())
  assert_eq(program.blocks().length(), 1)
  assert_eq(program.blocks()[0].words().length(), 0)
  assert_eq(program.blocks()[0].comment(), Some("setup only"))
}

///|
test "parser reports unclosed and nested comments" {
  let program = parse_program("G1 (outer (inner)")
  assert_true(parser_has_code(program, "parse.comment.nested"))
  assert_true(parser_has_code(program, "parse.comment.unclosed"))
}

///|
test "parser reports illegal characters" {
  let program = parse_program("G1 X1 @ Y2")
  assert_true(parser_has_code(program, "parse.character.illegal"))
  assert_true(!program.is_valid())
}

///|
test "parser reports unsupported letters" {
  let program = parse_program("Q1 G0")
  assert_true(parser_has_code(program, "parse.letter.illegal"))
  assert_eq(parser_first(program).words()[0].letter(), 'G')
}

///|
test "parser reports missing numeric value" {
  let program = parse_program("G X1")
  assert_true(parser_has_code(program, "parse.word.missing_value"))
}

///|
test "parser reports malformed numeric value" {
  let program = parse_program("G1 X.")
  assert_true(parser_has_code(program, "parse.word.invalid_number"))
}

///|
test "parser rejects nonfinite numeric values" {
  let program = parse_program("G1 X1e309 Ynan")
  assert_true(parser_has_code(program, "parse.word.nonfinite"))
  assert_true(!program.is_valid())
}

///|
test "parser reports duplicate sequence and checksum" {
  let program = parse_program("N1 N2 G0*1*2")
  assert_true(parser_has_code(program, "parse.sequence.duplicate"))
  assert_true(parser_has_code(program, "parse.checksum.duplicate"))
}

///|
test "parser reports invalid and mismatched checksum" {
  let invalid = parse_program("G0*abc")
  assert_true(parser_has_code(invalid, "parse.checksum.invalid"))
  let mismatch = parse_program("G0*0")
  assert_true(parser_has_code(mismatch, "parse.checksum.mismatch"))
}

///|
test "parser validates a matching XOR checksum" {
  // ASCII XOR of `G0` is 0x77 (119).
  let program = parse_program("G0*119")
  assert_true(program.is_valid())
  assert_eq(parser_first(program).checksum(), Some(119))
}

///|
test "canonical block and normalized program are deterministic" {
  let program = parse_program("n3 g01 x1.0 (note)\nM2 S100")
  assert_true(program.is_valid())
  assert_eq(canonical_block(program.blocks()[0]), "N3 G1 X1")
  assert_eq(
    normalize_program(program, preserve_comments=true),
    "N3 G1 X1 ;note\nM2 S100",
  )
}

///|
test "blank lines do not create blocks" {
  let program = parse_program("\n  \t\nG1\n")
  assert_true(program.is_valid())
  assert_eq(program.blocks().length(), 1)
}
