///|
fn test_profile_text() -> String {
  "MOONGCODE_PROFILE 1\n" +
  "name test-mill\n" +
  "axis X -10 120\n" +
  "axis Y 0 80\n" +
  "axis Z -20 5\n" +
  "max-feed 1200\n" +
  "rapid-feed 4000\n" +
  "max-spindle 18000\n" +
  "max-arc-radius 200\n" +
  "max-dwell 10\n" +
  "require-spindle true\n" +
  "allow-rapid-z-down false\n" +
  "allow-unsupported false\n" +
  "tools 0,1,2,7\n"
}

///|
test "parse complete machine profile" {
  let profile = parse_profile(test_profile_text()).unwrap()
  assert_eq(profile.name(), "test-mill")
  assert_true(profile.x().contains(-10.0))
  assert_false(profile.x().contains(121.0))
  assert_eq(profile.allowed_tools(), [0, 1, 2, 7])
  assert_true(profile.require_spindle_for_cut())
}

///|
test "profile serialization round trips" {
  let profile = parse_profile(test_profile_text()).unwrap()
  let reparsed = parse_profile(profile.to_text()).unwrap()
  assert_eq(profile, reparsed)
}

///|
test "desktop profile has bounded workspace" {
  let profile = MachineProfile::desktop_mill()
  assert_true(profile.x().contains(150.0))
  assert_false(profile.z().contains(21.0))
  assert_true(profile.allows_tool(10))
  assert_false(profile.allows_tool(11))
}

///|
test "axis limits reject reverse range" {
  assert_true(AxisLimits::new(1.0, 1.0) is Err(_))
  assert_true(AxisLimits::new(2.0, -2.0) is Err(_))
}

///|
test "profile requires header" {
  let result = parse_profile("name broken")
  assert_true(result is Err(_))
  match result {
    Err(items) => assert_eq(items[0].code(), "profile.header")
    Ok(_) => fail("expected error")
  }
}

///|
test "profile reports every missing field" {
  let result = parse_profile("MOONGCODE_PROFILE 1\nname sparse\n")
  match result {
    Err(items) => assert_true(items.length() >= 10)
    Ok(_) => fail("expected missing fields")
  }
}

///|
test "profile rejects duplicate axis" {
  let source = test_profile_text() + "axis X 0 1\n"
  match parse_profile(source) {
    Err(items) =>
      assert_true(items.any(fn(item) { item.code() == "profile.duplicate" }))
    Ok(_) => fail("expected duplicate")
  }
}

///|
test "profile rejects duplicate tool" {
  let source = test_profile_text().replace(
    old="tools 0,1,2,7",
    new="tools 0,1,1,7",
  )
  match parse_profile(source) {
    Err(items) =>
      assert_true(
        items.any(fn(item) { item.code() == "profile.tools.duplicate" }),
      )
    Ok(_) => fail("expected duplicate tool")
  }
}

///|
test "profile supports unrestricted tool marker" {
  let source = test_profile_text().replace(old="tools 0,1,2,7", new="tools *")
  let profile = parse_profile(source).unwrap()
  assert_true(profile.allows_tool(845))
}

///|
test "profile rejects unknown field" {
  let source = test_profile_text() + "mystery 5\n"
  match parse_profile(source) {
    Err(items) =>
      assert_true(items.any(fn(item) { item.code() == "profile.unknown" }))
    Ok(_) => fail("expected unknown field")
  }
}

///|
test "profile rejects non-finite and negative limits" {
  let source = test_profile_text().replace(
    old="max-feed 1200",
    new="max-feed -1",
  )
  match parse_profile(source) {
    Err(items) =>
      assert_true(items.any(fn(item) { item.code() == "profile.invalid" }))
    Ok(_) => fail("expected invalid profile")
  }
}

///|
test "profile handles CRLF and comments" {
  let source = (test_profile_text() + "# end\n").replace(old="\n", new="\r\n")
  assert_eq(parse_profile(source).unwrap().name(), "test-mill")
}
