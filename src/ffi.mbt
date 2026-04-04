///|
/// Returns the native platform code for the current process.
extern "C" fn platform_code_ffi() -> Int = "mb_replace_self_platform_code"

///|
/// Returns the current executable path in the native platform encoding, or an empty value.
extern "C" fn current_executable_path_ffi() -> Bytes = "mb_replace_self_current_executable_path"

///|
/// Replaces the current executable with `replacement_path`.
#borrow(replacement_path)
extern "C" fn replace_self_ffi(replacement_path : Bytes) -> Int = "mb_replace_self_replace_self"

///|
/// Deletes the current executable.
extern "C" fn delete_self_ffi() -> Int = "mb_replace_self_delete_self"

///|
/// Returns the last native error code observed by the C shim.
extern "C" fn last_error_code_ffi() -> Int = "mb_replace_self_last_error_code"

///|
/// Returns the last native error message as UTF-8 bytes.
extern "C" fn last_error_message_ffi() -> Bytes = "mb_replace_self_last_error_message"

///|
/// Decodes UTF-8 bytes into a MoonBit string with lossy fallback.
fn decode_utf8(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes[:])
}

///|
/// Decodes native text returned by the platform-specific shim.
fn decode_native_text(platform : Platform, bytes : Bytes) -> String {
  if bytes.length() == 0 {
    return ""
  }

  let value = match platform {
    Platform::Windows => @ffi.from_wstr_lossy(bytes)
    Platform::MacOS | Platform::Linux | Platform::Unsupported =>
      decode_utf8(bytes)
  }
  value
}

///|
/// Decodes optional text returned by the native layer.
fn decode_optional_text(platform : Platform, bytes : Bytes) -> String? {
  let value = decode_native_text(platform, bytes)
  if value.is_empty() {
    None
  } else {
    Some(value)
  }
}

///|
/// Decodes a native error message and falls back to `default_message`.
fn decode_error_message(bytes : Bytes, default_message : String) -> String {
  let message = decode_utf8(bytes)
  if message.is_empty() {
    default_message
  } else {
    message
  }
}

///|
/// Returns the last native error message or `default_message`.
fn last_error_message_or(default_message : String) -> String {
  decode_error_message(last_error_message_ffi(), default_message)
}

///|
/// Converts the last native failure into `ReplaceSelfError`.
fn native_failure(
  action : String,
  fallback_message : String,
) -> ReplaceSelfError {
  ignore(last_error_code_ffi())
  ReplaceSelfError::NativeFailure(
    action~,
    message=last_error_message_or(fallback_message),
  )
}

///|
/// Converts a native "0 means success" status code into `Result`.
fn unit_result_from_status(
  status : Int,
  action : String,
  fallback_message : String,
) -> Result[Unit, ReplaceSelfError] {
  if status == 0 {
    Ok(())
  } else {
    Err(native_failure(action, fallback_message))
  }
}

///|
/// Returns the current executable path or a typed discovery error.
fn current_executable_path_result() -> Result[String, ReplaceSelfError] {
  let platform = current_platform()
  match decode_optional_text(platform, current_executable_path_ffi()) {
    Some(path) => Ok(path)
    None => Err(ReplaceSelfError::ExecutablePathUnavailable)
  }
}
