///|
/// Checks whether `path` is absolute for `platform`.
fn is_absolute_path(platform : Platform, path : String) -> Bool {
  if path.is_empty() {
    return false
  }

  match platform {
    Platform::Windows => is_windows_absolute_path(path)
    Platform::MacOS | Platform::Linux =>
      path.code_unit_at(0) == '/'.to_int().to_uint16()
    Platform::Unsupported => false
  }
}

///|
/// Checks the Windows absolute-path forms accepted by the package.
fn is_windows_absolute_path(path : String) -> Bool {
  if path.length() >= 3 &&
    is_ascii_letter(path.code_unit_at(0)) &&
    path.code_unit_at(1) == ':'.to_int().to_uint16() &&
    (
      path.code_unit_at(2) == '\\'.to_int().to_uint16() ||
      path.code_unit_at(2) == '/'.to_int().to_uint16()
    ) {
    return true
  }

  path.length() >= 2 &&
  path.code_unit_at(0) == '\\'.to_int().to_uint16() &&
  path.code_unit_at(1) == '\\'.to_int().to_uint16()
}

///|
/// Checks whether `code_unit` is an ASCII letter.
fn is_ascii_letter(code_unit : UInt16) -> Bool {
  let code = code_unit.to_int()
  (code >= 'a'.to_int() && code <= 'z'.to_int()) ||
  (code >= 'A'.to_int() && code <= 'Z'.to_int())
}

///|
/// Trims leading and trailing Unicode whitespace.
fn trim_text(text : String) -> String {
  text.trim().to_string()
}

///|
/// Validates the replacement source path against the current platform.
fn validate_replacement_path(
  platform : Platform,
  replacement_path : String,
  current_executable_path : String,
) -> Result[String, ReplaceSelfError] {
  if platform == Platform::Unsupported {
    return Err(ReplaceSelfError::UnsupportedPlatform(platform))
  }

  let trimmed = trim_text(replacement_path)
  if trimmed.is_empty() {
    return Err(ReplaceSelfError::EmptyReplacementPath)
  }

  if !is_absolute_path(platform, trimmed) {
    return Err(ReplaceSelfError::RelativeReplacementPath(trimmed))
  }

  if trimmed == current_executable_path {
    return Err(ReplaceSelfError::ReplacementMatchesCurrentExecutable(trimmed))
  }

  Ok(trimmed)
}
