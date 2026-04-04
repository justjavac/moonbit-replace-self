///|
/// Replaces the current executable through injected dependencies.
fn replace_self_with(
  platform : Platform,
  new_executable : String,
  current_path_result : () -> Result[String, ReplaceSelfError],
  replace_action : (String) -> Result[Unit, ReplaceSelfError],
) -> Result[Unit, ReplaceSelfError] {
  match current_path_result() {
    Ok(current_path) =>
      match validate_replacement_path(platform, new_executable, current_path) {
        Ok(validated_path) => replace_action(validated_path)
        Err(error) => Err(error)
      }
    Err(error) => Err(error)
  }
}

///|
/// Deletes the current executable through injected dependencies.
fn delete_self_with(
  platform : Platform,
  current_path_result : () -> Result[String, ReplaceSelfError],
  delete_action : () -> Result[Unit, ReplaceSelfError],
) -> Result[Unit, ReplaceSelfError] {
  if platform == Platform::Unsupported {
    return Err(ReplaceSelfError::UnsupportedPlatform(platform))
  }

  match current_path_result() {
    Ok(_) => delete_action()
    Err(error) => Err(error)
  }
}

///|
/// Performs the native replace-self call.
fn replace_self_native_result(
  validated_path : String,
) -> Result[Unit, ReplaceSelfError] {
  unit_result_from_status(
    replace_self_ffi(@utf8.encode(validated_path)),
    "replace self",
    "Failed to replace the current executable",
  )
}

///|
/// Performs the native delete-self call.
fn delete_self_native_result() -> Result[Unit, ReplaceSelfError] {
  unit_result_from_status(
    delete_self_ffi(),
    "delete self",
    "Failed to delete the current executable",
  )
}

///|
/// Replaces the currently running executable with `new_executable`.
///
/// Use this when an application has already downloaded a new binary and wants
/// the current process image on disk to be swapped for that replacement.
///
/// # Arguments
///
/// - `new_executable`: absolute path to the replacement executable file. The
///   replacement file must already exist and must not be the same path as the
///   current executable.
///
/// # Returns
///
/// Returns `Ok(())` after the replacement has completed on Unix platforms, or
/// after the replacement helper has been scheduled successfully on Windows.
///
/// Platform behavior:
///
/// - Linux and macOS perform the replacement immediately with an atomic rename.
/// - Windows launches a detached helper script, then completes the replacement
///   after the current process exits and the executable file is unlocked.
///
/// On Windows, a successful return means the replacement was scheduled
/// successfully. Callers should exit soon after `Ok(())` so the helper can take
/// over and finish the move.
///
/// # Errors
///
/// Returns `Err(ReplaceSelfError)` when:
///
/// - the replacement path is empty after trimming whitespace
/// - the replacement path is not absolute for the current platform
/// - the replacement path matches the current executable path
/// - the current executable path cannot be discovered
/// - the host platform is unsupported
/// - the native platform API rejects the replacement request
///
/// # Example
/// ```mbt nocheck
/// match @replace_self.replace_self("/tmp/app.next") {
///   Ok(()) => ()
///   Err(error) => println(error)
/// }
/// ```
pub fn replace_self(new_executable : String) -> Result[Unit, ReplaceSelfError] {
  replace_self_with(
    current_platform(),
    new_executable,
    current_executable_path_result,
    replace_self_native_result,
  )
}

///|
/// Deletes the currently running executable.
///
/// Use this when a process should remove its own executable file after it has
/// finished running, such as a one-shot bootstrapper or an uninstall helper.
///
/// # Returns
///
/// Returns `Ok(())` after the file has been unlinked on Unix platforms, or
/// after the deletion helper has been scheduled successfully on Windows.
///
/// Platform behavior:
///
/// - Linux and macOS unlink the file immediately.
/// - Windows launches a detached helper script that waits for the process to
///   exit, then removes the executable file.
///
/// On Windows, a successful return means deletion was scheduled successfully.
/// Callers should exit soon after `Ok(())` so the helper can remove the file.
///
/// # Errors
///
/// Returns `Err(ReplaceSelfError)` when:
///
/// - the current executable path cannot be discovered
/// - the host platform is unsupported
/// - the native platform API rejects the deletion request
pub fn delete_self() -> Result[Unit, ReplaceSelfError] {
  delete_self_with(
    current_platform(),
    current_executable_path_result,
    delete_self_native_result,
  )
}
