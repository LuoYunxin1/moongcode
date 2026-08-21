///|
fn split_source_lines(source : String) -> Array[String] {
  source
  .split("\n")
  .map(fn(view) {
    let line = view.to_owned()
    if line.has_suffix("\r") {
      line[:line.length() - 1].to_owned()
    } else {
      line
    }
  })
  .collect()
}

///|
pub fn split_ascii_fields(source : String) -> Array[String] {
  let fields : Array[String] = []
  let mut current = StringBuilder::new()
  let mut has_current = false
  let flush = fn() {
    if has_current {
      fields.push(current.to_string())
      current = StringBuilder::new()
      has_current = false
    }
  }
  for char in source {
    if char == ' ' || char == '\t' {
      flush()
    } else {
      current.write_char(char)
      has_current = true
    }
  }
  flush()
  fields
}

///|
pub fn parse_finite_double(
  source : String,
  code : String,
  line : Int,
  column : Int,
) -> Result[Double, Diagnostic] {
  let chars = source.to_array()
  if chars.is_empty() {
    return Err(
      Diagnostic::error(code, line, column, "expected a decimal number"),
    )
  }
  let mut index = 0
  let mut sign = 1.0
  if chars[index] == '-' || chars[index] == '+' {
    if chars[index] == '-' {
      sign = -1.0
    }
    index = index + 1
  }
  let mut whole = 0.0
  let mut digit_count = 0
  while index < chars.length() && chars[index] >= '0' && chars[index] <= '9' {
    whole = whole * 10.0 + (chars[index].to_int() - '0'.to_int()).to_double()
    digit_count = digit_count + 1
    index = index + 1
  }
  let mut fraction = 0.0
  let mut divisor = 1.0
  if index < chars.length() && chars[index] == '.' {
    index = index + 1
    while index < chars.length() && chars[index] >= '0' && chars[index] <= '9' {
      fraction = fraction * 10.0 +
        (chars[index].to_int() - '0'.to_int()).to_double()
      divisor = divisor * 10.0
      digit_count = digit_count + 1
      index = index + 1
    }
  }
  if digit_count == 0 {
    return Err(
      Diagnostic::error(
        code,
        line,
        column,
        "expected a finite decimal number, got " + source,
      ),
    )
  }
  let mut exponent = 0
  let mut exponent_sign = 1
  if index < chars.length() && (chars[index] == 'e' || chars[index] == 'E') {
    index = index + 1
    if index < chars.length() && (chars[index] == '-' || chars[index] == '+') {
      if chars[index] == '-' {
        exponent_sign = -1
      }
      index = index + 1
    }
    let exponent_start = index
    while index < chars.length() && chars[index] >= '0' && chars[index] <= '9' {
      exponent = exponent * 10 + chars[index].to_int() - '0'.to_int()
      if exponent > 308 {
        return Err(
          Diagnostic::error(
            code, line, column, "decimal exponent is outside bounds",
          ),
        )
      }
      index = index + 1
    }
    if exponent_start == index {
      return Err(
        Diagnostic::error(code, line, column, "decimal exponent has no digits"),
      )
    }
  }
  if index != chars.length() {
    return Err(
      Diagnostic::error(
        code,
        line,
        column,
        "expected a finite decimal number, got " + source,
      ),
    )
  }
  let mut value = sign * (whole + fraction / divisor)
  for iteration = 0; iteration < exponent; iteration = iteration + 1 {
    value = if exponent_sign > 0 { value * 10.0 } else { value / 10.0 }
  }
  if value.is_nan() || value.is_inf() {
    Err(Diagnostic::error(code, line, column, "number must be finite"))
  } else {
    Ok(value)
  }
}

///|
pub fn parse_bounded_int(
  source : String,
  minimum : Int,
  maximum : Int,
  code : String,
  line : Int,
) -> Result[Int, Diagnostic] {
  if source.is_empty() {
    return Err(Diagnostic::error(code, line, 1, "expected an integer"))
  }
  let mut value = 0
  for char in source {
    if char < '0' || char > '9' {
      return Err(
        Diagnostic::error(code, line, 1, "expected an integer, got " + source),
      )
    }
    value = value * 10 + char.to_int() - '0'.to_int()
    if value > maximum {
      return Err(
        Diagnostic::error(
          code,
          line,
          1,
          "integer must be between " +
          minimum.to_string() +
          " and " +
          maximum.to_string(),
        ),
      )
    }
  }
  if value < minimum || value > maximum {
    Err(
      Diagnostic::error(
        code,
        line,
        1,
        "integer must be between " +
        minimum.to_string() +
        " and " +
        maximum.to_string(),
      ),
    )
  } else {
    Ok(value)
  }
}

///|
fn parse_strict_bool(
  source : String,
  code : String,
  line : Int,
) -> Result[Bool, Diagnostic] {
  match source {
    "true" => Ok(true)
    "false" => Ok(false)
    _ =>
      Err(
        Diagnostic::error(
          code,
          line,
          1,
          "expected true or false, got " + source,
        ),
      )
  }
}
