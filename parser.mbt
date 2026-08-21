///|
/// Deterministic G-code lexer and line-oriented program parser.
///
/// The parser deliberately keeps the domain model small: each physical source
/// line becomes at most one `Block`, comments are kept separately, and all
/// diagnostics are returned instead of raising.  This makes malformed input
/// safe to inspect in tooling and in safety preflight workflows.
let parser_allowed_letters : String = "GMXYZIJKRFSTPLHDEN"

///|
fn parser_is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
fn parser_is_allowed_letter(c : Char) -> Bool {
  parser_allowed_letters.contains_char(c.to_ascii_uppercase())
}

///|
fn parser_letter_rank(c : Char) -> Int {
  match c {
    'G' => 0
    'M' => 1
    'X' => 2
    'Y' => 3
    'Z' => 4
    'I' => 5
    'J' => 6
    'K' => 7
    'R' => 8
    'F' => 9
    'S' => 10
    'T' => 11
    'P' => 12
    'L' => 13
    'H' => 14
    'D' => 15
    'E' => 16
    _ => 99
  }
}

///|
fn parser_is_number_start(c : Char) -> Bool {
  c.is_ascii_digit() || c == '+' || c == '-' || c == '.'
}

///|
fn parser_digit(c : Char) -> Int? {
  if c.is_ascii_digit() {
    Some(c.to_int() - '0'.to_int())
  } else {
    None
  }
}

///|
fn parser_string_char(source : String, index : Int) -> Char? {
  source.get_char(index)
}

///|
fn parser_slice(source : String, start : Int, end : Int) -> String {
  source[start:end].to_owned()
}

///|
fn parser_is_line_end(source : String, index : Int) -> Bool {
  index >= source.length()
}

///|
fn parser_code_column(index : Int) -> Int {
  // Public diagnostics use one-based columns.
  index + 1
}

///|
fn parser_push_error(
  diagnostics : Array[Diagnostic],
  code : String,
  line : Int,
  column : Int,
  message : String,
) -> Unit {
  diagnostics.push(Diagnostic::error(code, line, column, message))
}

///|
fn parser_is_letter(c : Char) -> Bool {
  c.is_ascii_alphabetic()
}

///|
fn parser_is_exponent_marker(
  source : String,
  index : Int,
  current_letter : Char,
) -> Bool {
  let c = match parser_string_char(source, index) {
    Some(value) => value
    None => return false
  }
  if c != 'e' && c != 'E' {
    return false
  }
  // An uppercase E is also a legal G-code address.  Keep the compact form
  // `G1E-2` unambiguous as two words while accepting scientific notation for
  // axis/feed words and lowercase `e` in all contexts.
  if c == 'E' && current_letter == 'G' {
    return false
  }
  let next = index + 1
  if parser_is_line_end(source, next) {
    return false
  }
  let next_char = parser_string_char(source, next).unwrap()
  if next_char == '+' || next_char == '-' {
    let after_sign = next + 1
    if parser_is_line_end(source, after_sign) {
      return false
    }
    return parser_string_char(source, after_sign).unwrap().is_ascii_digit()
  }
  next_char.is_ascii_digit()
}

///|
fn parser_scan_number_end(
  source : String,
  start : Int,
  current_letter : Char,
) -> Int {
  let mut index = start
  let length = source.length()
  if index < length {
    let sign = source.get_char(index).unwrap()
    if sign == '+' || sign == '-' {
      index += 1
    }
  }
  let mut digits_before = 0
  while index < length && source.get_char(index).unwrap().is_ascii_digit() {
    digits_before += 1
    index += 1
  }
  if index < length && source.get_char(index).unwrap() == '.' {
    index += 1
    while index < length && source.get_char(index).unwrap().is_ascii_digit() {
      index += 1
    }
  }
  if digits_before > 0 || (index > start && index - 1 < length) {
    if index < length &&
      parser_is_exponent_marker(source, index, current_letter) {
      index += 1
      if index < length {
        let sign = source.get_char(index).unwrap()
        if sign == '+' || sign == '-' {
          index += 1
        }
      }
      while index < length && source.get_char(index).unwrap().is_ascii_digit() {
        index += 1
      }
    }
  }
  index
}

///|
fn parser_parse_decimal(raw : String) -> (Double, Bool) {
  // Return `(value, syntax_ok)`.  The scanner has already isolated the raw
  // token; this routine intentionally rejects NaN/Infinity spellings.
  let length = raw.length()
  if length == 0 {
    return (0.0, false)
  }
  let mut index = 0
  let mut negative = false
  let first = raw.get_char(0).unwrap()
  if first == '+' || first == '-' {
    negative = first == '-'
    index = 1
  }
  let mut mantissa : Double = 0.0
  let mut mantissa_digits = 0
  let mut fractional_digits = 0
  while index < length {
    let c = raw.get_char(index).unwrap()
    match parser_digit(c) {
      Some(digit) => {
        mantissa = mantissa * 10.0 + digit.to_double()
        mantissa_digits += 1
        if fractional_digits > 0 {
          fractional_digits += 1
        }
        index += 1
      }
      None => break
    }
  }
  if index < length && raw.get_char(index).unwrap() == '.' {
    index += 1
    while index < length {
      let c = raw.get_char(index).unwrap()
      match parser_digit(c) {
        Some(digit) => {
          mantissa = mantissa * 10.0 + digit.to_double()
          mantissa_digits += 1
          fractional_digits += 1
          index += 1
        }
        None => break
      }
    }
  }
  if mantissa_digits == 0 {
    return (0.0, false)
  }
  let mut exponent : Int = 0
  if index < length {
    let marker = raw.get_char(index).unwrap()
    if marker != 'e' && marker != 'E' {
      return (0.0, false)
    }
    index += 1
    let mut exponent_negative = false
    if index < length {
      let sign = raw.get_char(index).unwrap()
      if sign == '+' || sign == '-' {
        exponent_negative = sign == '-'
        index += 1
      }
    }
    let mut exponent_digits = 0
    while index < length {
      match parser_digit(raw.get_char(index).unwrap()) {
        Some(digit) => {
          // Clamping keeps malformed/huge exponents deterministic and avoids
          // integer overflow before the finite-value check below.
          if exponent < 10000 {
            exponent = exponent * 10 + digit
            if exponent > 10000 {
              exponent = 10000
            }
          }
          exponent_digits += 1
          index += 1
        }
        None => return (0.0, false)
      }
    }
    if exponent_digits == 0 {
      return (0.0, false)
    }
    if exponent_negative {
      exponent = -exponent
    }
  }
  if index != length {
    return (0.0, false)
  }
  let decimal_exponent = exponent - fractional_digits
  let mut value = mantissa
  if decimal_exponent != 0 {
    // `@math.pow` is available through the package's existing math import.
    value = value * @math.pow(10.0, decimal_exponent.to_double())
  }
  if negative {
    value = -value
  }
  (value, true)
}

///|
fn parser_parse_int(raw : String) -> (Int, Bool) {
  let length = raw.length()
  if length == 0 {
    return (0, false)
  }
  let mut index = 0
  let mut negative = false
  let first = raw.get_char(0).unwrap()
  if first == '+' || first == '-' {
    negative = first == '-'
    index = 1
  }
  if index == length {
    return (0, false)
  }
  let mut value : Int = 0
  let mut digits = 0
  while index < length {
    let c = raw.get_char(index).unwrap()
    match parser_digit(c) {
      Some(digit) => {
        // G-code sequence/checksum values are small; reject rather than wrap.
        if value > 214748364 {
          return (0, false)
        }
        value = value * 10 + digit
        digits += 1
        index += 1
      }
      None => return (0, false)
    }
  }
  if digits == 0 {
    return (0, false)
  }
  if negative {
    value = -value
  }
  (value, true)
}

///|
fn parser_comment_join(parts : Array[String]) -> String? {
  let mut result = ""
  for part in parts {
    let cleaned = part.trim().to_owned()
    if !cleaned.is_empty() {
      if !result.is_empty() {
        result += " "
      }
      result += cleaned
    }
  }
  if result.is_empty() {
    None
  } else {
    Some(result)
  }
}

///|
priv struct ScannedLine {
  code : String
  comments : Array[String]
  checksum_raw : String?
  checksum_column : Int
  diagnostics : Array[Diagnostic]
}

///|
fn parser_scan_line(source : String, line : Int) -> ScannedLine {
  let mut code = ""
  let comments : Array[String] = []
  let diagnostics : Array[Diagnostic] = []
  let mut index = 0
  let length = source.length()
  let mut in_comment = false
  let mut comment_depth = 0
  let mut comment_start = 0
  let mut comment_text = ""
  let mut checksum_raw : String? = None
  let mut checksum_column = 0
  let mut checksum_buffer = ""
  let mut after_checksum = false
  while index < length {
    let c = source.get_char(index).unwrap()
    if in_comment {
      if c == '(' {
        comment_depth += 1
        parser_push_error(
          diagnostics,
          "parse.comment.nested",
          line,
          parser_code_column(index),
          "nested parenthesis comment",
        )
      } else if c == ')' {
        comment_depth -= 1
        if comment_depth == 0 {
          in_comment = false
          comments.push(comment_text)
          comment_text = ""
        } else {
          comment_text += String::from_array([c])
        }
      } else {
        comment_text += String::from_array([c])
      }
      index += 1
      continue
    }
    if c == '(' {
      in_comment = true
      comment_depth = 1
      comment_start = index
      comment_text = ""
      index += 1
      continue
    }
    if c == ';' {
      let rest = parser_slice(source, index + 1, length)
      comments.push(rest.trim().to_owned())
      break
    }
    if c == '*' {
      if after_checksum {
        parser_push_error(
          diagnostics,
          "parse.checksum.duplicate",
          line,
          parser_code_column(index),
          "duplicate checksum marker",
        )
      } else {
        checksum_column = parser_code_column(index)
        after_checksum = true
      }
      index += 1
      continue
    }
    if after_checksum {
      // A checksum is a decimal token.  Keep scanning after whitespace so
      // comments and duplicate markers can still be diagnosed.
      if c == '(' {
        in_comment = true
        comment_depth = 1
        comment_start = index
        comment_text = ""
      } else if c == ';' {
        let rest = parser_slice(source, index + 1, length)
        comments.push(rest.trim().to_owned())
        break
      } else if !parser_is_space(c) {
        checksum_buffer += String::from_array([c])
      }
      index += 1
      continue
    }
    code += String::from_array([c])
    index += 1
  }
  if in_comment {
    parser_push_error(
      diagnostics,
      "parse.comment.unclosed",
      line,
      parser_code_column(comment_start),
      "unclosed parenthesis comment",
    )
  }
  if after_checksum {
    checksum_raw = Some(checksum_buffer.trim().to_owned())
  }
  { code, comments, checksum_raw, checksum_column, diagnostics }
}

///|
fn parser_xor_checksum(source : String) -> Int {
  let mut value = 0
  for c in source.iter() {
    value = value ^ (c.to_int() & 255)
  }
  value
}

///|
fn parser_checksum_diagnostic(
  scanned : ScannedLine,
  line : Int,
  raw_line : String,
  diagnostics : Array[Diagnostic],
) -> Int? {
  match scanned.checksum_raw {
    None => None
    Some(raw) => {
      let (value, ok) = parser_parse_int(raw)
      if !ok {
        parser_push_error(
          diagnostics,
          "parse.checksum.invalid",
          line,
          scanned.checksum_column + 1,
          "checksum must be a decimal integer",
        )
        None
      } else {
        let marker = raw_line.find("*")
        let expected = match marker {
          Some(position) =>
            parser_xor_checksum(parser_slice(raw_line, 0, position))
          None => 0
        }
        if value != expected {
          parser_push_error(
            diagnostics,
            "parse.checksum.mismatch",
            line,
            scanned.checksum_column,
            "checksum XOR does not match line",
          )
        }
        Some(value)
      }
    }
  }
}

///|
fn parser_parse_line(
  raw_line : String,
  line : Int,
) -> (Block?, Array[Diagnostic]) {
  let scanned = parser_scan_line(raw_line, line)
  let diagnostics = scanned.diagnostics.copy()
  let checksum = parser_checksum_diagnostic(
    scanned, line, raw_line, diagnostics,
  )
  let code = scanned.code
  let mut index = 0
  let length = code.length()
  let mut sequence : Int? = None
  let words : Array[Word] = []
  let mut saw_content = false
  while index < length {
    let c = code.get_char(index).unwrap()
    if parser_is_space(c) {
      index += 1
      continue
    }
    saw_content = true
    if !parser_is_letter(c) {
      parser_push_error(
        diagnostics,
        "parse.character.illegal",
        line,
        parser_code_column(index),
        "illegal character in G-code block",
      )
      index += 1
      continue
    }
    let letter = c.to_ascii_uppercase()
    if !parser_is_allowed_letter(letter) {
      parser_push_error(
        diagnostics,
        "parse.letter.illegal",
        line,
        parser_code_column(index),
        "unsupported G-code address",
      )
      index += 1
      // Consume the malformed token to avoid cascading diagnostics.
      while index < length {
        let tail = code.get_char(index).unwrap()
        if parser_is_space(tail) || parser_is_letter(tail) {
          break
        }
        index += 1
      }
      continue
    }
    let value_start = index + 1
    if value_start >= length ||
      !parser_is_number_start(code.get_char(value_start).unwrap()) {
      // Recognize explicit non-finite spellings for a stable, dedicated code.
      let tail = parser_slice(code, value_start, length).to_lower()
      if tail.has_prefix("nan") || tail.has_prefix("inf") {
        parser_push_error(
          diagnostics,
          "parse.word.nonfinite",
          line,
          parser_code_column(value_start),
          "word value must be finite",
        )
      } else {
        parser_push_error(
          diagnostics,
          "parse.word.missing_value",
          line,
          parser_code_column(value_start),
          "word is missing a numeric value",
        )
      }
      index = value_start
      continue
    }
    let end = parser_scan_number_end(code, value_start, letter)
    let raw = parser_slice(code, value_start, end)
    let (value, syntax_ok) = parser_parse_decimal(raw)
    if !syntax_ok {
      parser_push_error(
        diagnostics,
        "parse.word.invalid_number",
        line,
        parser_code_column(value_start),
        "invalid numeric word value",
      )
    } else if value.is_nan() || value.is_inf() {
      parser_push_error(
        diagnostics,
        "parse.word.nonfinite",
        line,
        parser_code_column(value_start),
        "word value must be finite",
      )
    } else if letter == 'N' {
      let (sequence_value, sequence_ok) = parser_parse_int(raw)
      if !sequence_ok {
        parser_push_error(
          diagnostics,
          "parse.sequence.invalid",
          line,
          parser_code_column(value_start),
          "sequence number must be an integer",
        )
      } else if sequence is Some(_) {
        parser_push_error(
          diagnostics,
          "parse.sequence.duplicate",
          line,
          parser_code_column(index),
          "duplicate sequence number",
        )
      } else {
        sequence = Some(sequence_value)
      }
    } else {
      words.push(
        Word::new(
          letter,
          value,
          letter.to_string() + raw,
          parser_code_column(index),
        ),
      )
    }
    if end <= index {
      index += 1
    } else {
      index = end
    }
  }
  let comment = parser_comment_join(scanned.comments)
  if !saw_content && comment is None && checksum is None {
    return (None, diagnostics)
  }
  let block = Block::new(line, sequence, words, comment, checksum, raw_line)
  (Some(block), diagnostics)
}

///|
/// Parse a complete G-code source into blocks and stable diagnostics.
pub fn parse_program(source : String) -> Program {
  let blocks : Array[Block] = []
  let diagnostics : Array[Diagnostic] = []
  let mut line_number = 1
  for line_view in source.split("\n") {
    let mut raw_line = line_view.to_owned()
    if raw_line.has_suffix("\r") {
      raw_line = parser_slice(raw_line, 0, raw_line.length() - 1)
    }
    let trimmed = raw_line.trim().to_owned()
    if trimmed == "%" {
      line_number += 1
      continue
    }
    if trimmed.is_empty() {
      line_number += 1
      continue
    }
    let (block, line_diagnostics) = parser_parse_line(raw_line, line_number)
    for item in line_diagnostics {
      diagnostics.push(item)
    }
    match block {
      Some(value) => blocks.push(value)
      None => ()
    }
    line_number += 1
  }
  Program::new(blocks, diagnostics)
}

///|
fn parser_format_number(value : Double) -> String {
  // Double::to_string is deterministic across MoonBit targets and avoids
  // locale-dependent formatting.
  value.to_string()
}

///|
/// Return one canonical block line.  Sequence numbers are intentionally
/// omitted from words because they are represented by `Block.sequence`.
pub fn canonical_block(
  block : Block,
  preserve_comment? : Bool = false,
) -> String {
  let mut result = ""
  match block.sequence() {
    Some(value) => result += "N" + value.to_string()
    None => ()
  }
  // Sort by address then source column so equivalent blocks normalize to the
  // same text while repeated addresses remain deterministic.
  let words = block.words()
  words.sort_by(fn(left, right) {
    let letter_order = parser_letter_rank(left.letter()) -
      parser_letter_rank(right.letter())
    if letter_order != 0 {
      letter_order
    } else {
      left.column() - right.column()
    }
  })
  for word in words {
    if !result.is_empty() {
      result += " "
    }
    result += word.letter().to_string() + parser_format_number(word.value())
  }
  match block.checksum() {
    Some(value) => {
      if !result.is_empty() {
        result += " "
      }
      result += "*" + value.to_string()
    }
    None => ()
  }
  if preserve_comment == true {
    match block.comment() {
      Some(comment) => {
        if !result.is_empty() {
          result += " "
        }
        result += ";" + comment
      }
      None => ()
    }
  }
  result
}

///|
/// Normalize all blocks to deterministic canonical lines separated by `\n`.
pub fn normalize_program(
  program : Program,
  preserve_comments? : Bool = false,
) -> String {
  let mut result = ""
  let blocks = program.blocks()
  for index, block in blocks.iter2() {
    if index > 0 {
      result += "\n"
    }
    result += canonical_block(block, preserve_comment=preserve_comments)
  }
  result
}
