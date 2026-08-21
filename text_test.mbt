///|
test "finite decimal parser accepts G-code forms" {
  assert_eq(parse_finite_double("0", "test", 1, 1), Ok(0.0))
  assert_eq(parse_finite_double("-12.5", "test", 1, 1), Ok(-12.5))
  assert_eq(parse_finite_double(".25", "test", 1, 1), Ok(0.25))
  assert_eq(parse_finite_double("1.25e2", "test", 1, 1), Ok(125.0))
  assert_eq(parse_finite_double("4E-2", "test", 1, 1), Ok(0.04))
}

///|
test "finite decimal parser rejects malformed values" {
  assert_true(parse_finite_double("", "test", 1, 1) is Err(_))
  assert_true(parse_finite_double("+", "test", 1, 1) is Err(_))
  assert_true(parse_finite_double("1.2.3", "test", 1, 1) is Err(_))
  assert_true(parse_finite_double("1e", "test", 1, 1) is Err(_))
  assert_true(parse_finite_double("1e309", "test", 1, 1) is Err(_))
}

///|
test "field splitter accepts spaces and tabs" {
  assert_eq(split_ascii_fields("  axis\tX  0  10 "), ["axis", "X", "0", "10"])
}

///|
test "bounded integer parser rejects signs and overflow" {
  assert_eq(parse_bounded_int("12", 0, 20, "test", 1), Ok(12))
  assert_true(parse_bounded_int("-1", 0, 20, "test", 1) is Err(_))
  assert_true(parse_bounded_int("21", 0, 20, "test", 1) is Err(_))
}
