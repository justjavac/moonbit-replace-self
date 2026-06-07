///|
/// Checks whether `path` is absolute for `platform`.
fn is_absolute_path(platform : Platform, path : String) -> Bool {
  if path.is_empty() {
    return false
  }

  match platform {
    Windows => is_windows_absolute_path(path)
    MacOS | Linux => is_unix_absolute_path(path)
    Unsupported => false
  }
}

///|
/// Checks the Unix absolute-path form accepted by the package.
fn is_unix_absolute_path(path : String) -> Bool {
  path.code_unit_at(0) == '/'
}

///|
/// Checks the Windows absolute-path forms accepted by the package.
fn is_windows_absolute_path(path : String) -> Bool {
  is_windows_drive_absolute_path(path) || is_windows_unc_path(path)
}

///|
/// Checks the `C:\path` and `C:/path` Windows absolute-path forms.
fn is_windows_drive_absolute_path(path : String) -> Bool {
  path.length() >= 3 &&
  is_ascii_letter(path.code_unit_at(0)) &&
  path.code_unit_at(1) == ':' &&
  is_windows_separator(path.code_unit_at(2))
}

///|
/// Checks the UNC `\\server\share` Windows absolute-path form.
fn is_windows_unc_path(path : String) -> Bool {
  path.length() >= 2 &&
  path.code_unit_at(0) == '\\' &&
  path.code_unit_at(1) == '\\'
}

///|
/// Checks whether `code_unit` is a Windows path separator.
fn is_windows_separator(code_unit : UInt16) -> Bool {
  code_unit == '\\' || code_unit == '/'
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
  text.trim().to_owned()
}

///|
/// Validates the replacement source path against the current platform.
fn validate_replacement_path(
  platform : Platform,
  replacement_path : String,
  current_executable_path : String,
) -> Result[String, ReplaceSelfError] {
  if platform == Unsupported {
    return Err(UnsupportedPlatform(platform))
  }

  let trimmed = trim_text(replacement_path)
  if trimmed.is_empty() {
    return Err(EmptyReplacementPath)
  }

  if !is_absolute_path(platform, trimmed) {
    return Err(RelativeReplacementPath(trimmed))
  }

  if trimmed == current_executable_path {
    return Err(ReplacementMatchesCurrentExecutable(trimmed))
  }

  Ok(trimmed)
}
