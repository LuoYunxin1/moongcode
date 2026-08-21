///|
/// Stable textual views for parsed G-code.
///
/// The parser keeps source spelling in `Word.raw` and `Block.raw`; rendering is
/// intentionally independent of those fields so reports remain deterministic
/// across equivalent input spellings.  Checksums are retained verbatim when a
/// block has one.  This avoids silently discarding transport metadata; callers
/// that reorder or edit words should recalculate the checksum before sending a
/// normalized program to a controller.
fn render_letter_rank(letter : Char) -> Int {
  match letter {
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
fn render_number(value : Double, letter : Char) -> String {
  // Equality deliberately folds both +0.0 and -0.0 to the canonical `0`.
  if value == 0.0 {
    "0"
  } else if (letter == 'G' || letter == 'M') && value == value.trunc() {
    value.trunc().to_string()
  } else {
    value.to_string()
  }
}

///|
fn render_sorted_words(block : Block) -> Array[Word] {
  let words = block.words()
  words.sort_by(fn(left, right) {
    let rank = render_letter_rank(left.letter()) -
      render_letter_rank(right.letter())
    if rank != 0 {
      rank
    } else {
      // Source columns are one-based and provide a deterministic tie-breaker
      // for repeated addresses (e.g. `X1 X2`).
      left.column() - right.column()
    }
  })
  words
}

///|
/// Normalize one block into a stable, space-separated line.
///
/// Words are ordered by the documented address order (`G`, `M`, axes, arc
/// offsets, feed/spindle/tool and auxiliary addresses).  Sequence numbers are
/// emitted first.  Comments are omitted unless `preserve_comment` is true;
/// parsed checksums are retained after the words.
pub fn normalize_block(
  block : Block,
  preserve_comment? : Bool = false,
) -> String {
  let mut result = ""
  match block.sequence() {
    Some(sequence) => result += "N" + sequence.to_string()
    None => ()
  }
  for word in render_sorted_words(block) {
    if !result.is_empty() {
      result += " "
    }
    let letter = word.letter()
    result += letter.to_string() + render_number(word.value(), letter)
  }
  match block.checksum() {
    Some(checksum) => {
      if !result.is_empty() {
        result += " "
      }
      result += "*" + checksum.to_string()
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
fn render_diagnostic_lines(diagnostics : Array[Diagnostic]) -> String {
  let mut result = ""
  for diagnostic in diagnostics {
    if !result.is_empty() {
      result += "\n"
    }
    result += "- " + diagnostic.to_text()
  }
  result
}

///|
/// Return a stable human-readable validation report for a parsed program.
///
/// The report contains no source-dependent memory addresses or timestamps.  A
/// valid report has exactly two lines; an invalid report appends diagnostics in
/// parser order, preserving their stable code/line/column fields.
pub fn validate_report(program : Program) -> String {
  let diagnostics = program.diagnostics()
  let header = if diagnostics_have_errors(diagnostics) {
    "INVALID"
  } else {
    "VALID"
  }
  let mut result = header + "\nblocks: " + program.blocks().length().to_string()
  if !diagnostics.is_empty() {
    result += "\ndiagnostics:\n" + render_diagnostic_lines(diagnostics)
  }
  result
}

///|
/// Explain one parsed block without exposing its original whitespace.
pub fn explain_block(block : Block) -> String {
  let mut result = "line " + block.source_line().to_string()
  match block.sequence() {
    Some(sequence) => result += " sequence=" + sequence.to_string()
    None => ()
  }
  result += " words=" + block.words().length().to_string()
  match block.comment() {
    Some(comment) => result += " comment=" + comment
    None => ()
  }
  match block.checksum() {
    Some(checksum) => result += " checksum=" + checksum.to_string()
    None => ()
  }
  result += " | " + normalize_block(block)
  result
}

///|
fn render_line_diagnostics(
  diagnostics : Array[Diagnostic],
  line : Int,
) -> Array[Diagnostic] {
  diagnostics.filter(fn(item) { item.line() == line })
}

///|
/// Parse and explain one physical source line.
///
/// `line_number` is one-based.  Errors for the selected line are returned as
/// `Err`; a blank or comment-free line gets a stable `render.line.empty`
/// diagnostic.  Diagnostics on unrelated lines do not prevent explaining the
/// requested valid line.
pub fn explain_line(
  source : String,
  line_number? : Int = 1,
) -> Result[String, Array[Diagnostic]] {
  if line_number < 1 {
    return Err([
      Diagnostic::error(
        "render.line.range", line_number, 1, "line number must be at least 1",
      ),
    ])
  }
  let program = parse_program(source)
  let line_diagnostics = render_line_diagnostics(
    program.diagnostics(),
    line_number,
  )
  if !line_diagnostics.is_empty() {
    return Err(line_diagnostics)
  }
  for block in program.blocks() {
    if block.source_line() == line_number {
      return Ok(explain_block(block))
    }
  }
  Err([
    Diagnostic::error(
      "render.line.empty", line_number, 1, "line does not contain a G-code block",
    ),
  ])
}

///|
/// Explain every parsed block in source order, one block per line.
pub fn explain_program(program : Program) -> String {
  let mut result = ""
  for block in program.blocks() {
    if !result.is_empty() {
      result += "\n"
    }
    result += explain_block(block)
  }
  result
}

///|
/// Render modal before/after state for every executed source block.
pub fn execution_trace_text(execution : Execution) -> String {
  let mut result = "TRACE"
  for step in execution.steps() {
    result += "\nline " + step.source_line().to_string()
    result += " " + step.before().position().to_text()
    result += " -> " + step.after().position().to_text()
    result += " mode=" + step.after().motion().to_text()
    result += " units=" + step.after().units().to_text()
    result += " segments=" + step.segments().length().to_string()
    for diagnostic in step.diagnostics() {
      result += "\n  " + diagnostic.to_text()
    }
  }
  result
}
