///|
/// Sleeps for at least `milliseconds`.
extern "C" fn sleep_millis_for_test(milliseconds : Int) -> Unit = "mb_replace_self_sleep_millis"

///|
/// Joins path segments with the platform separator.
fn join_path_for_test(platform : Platform, parts : Array[String]) -> String {
  match platform {
    Windows => parts.join("\\")
    _ => parts.join("/")
  }
}

///|
/// Polls until `predicate` succeeds or the timeout elapses.
fn wait_until_for_test(
  timeout_millis : Int,
  interval_millis : Int,
  predicate : () -> Bool,
) -> Bool {
  for waited = 0 {
    if waited > timeout_millis {
      break false
    }
    if predicate() {
      break true
    }
    sleep_millis_for_test(interval_millis)
    continue waited + interval_millis
  }
}

///|
test "platform code mapping is stable" {
  assert_eq(platform_from_code(1), Windows)
  assert_eq(platform_from_code(2), MacOS)
  assert_eq(platform_from_code(3), Linux)
  assert_eq(platform_from_code(0), Unsupported)
}

///|
test "replace_self_with succeeds for a valid absolute path" {
  let result = replace_self_with(
    Windows,
    "C:\\temp\\next.exe",
    fn() { Ok("C:\\temp\\current.exe") },
    fn(_) { Ok(()) },
  )
  assert_true(result == Ok(()))
}

///|
test "replace_self_with propagates current path failures" {
  let result = replace_self_with(
    Linux,
    "/tmp/next",
    fn() { Err(ExecutablePathUnavailable) },
    fn(_) { Ok(()) },
  )
  assert_true(result == Err(ExecutablePathUnavailable))
}

///|
test "delete_self_with succeeds when dependencies succeed" {
  let result = delete_self_with(MacOS, fn() { Ok("/Applications/demo") }, fn() {
    Ok(())
  })
  assert_true(result == Ok(()))
}

///|
test "delete_self_with rejects unsupported platforms" {
  let result = delete_self_with(Unsupported, fn() { Ok("ignored") }, fn() {
    Ok(())
  })
  assert_true(result == Err(UnsupportedPlatform(Unsupported)))
}

///|
test "join_path uses platform separators" {
  assert_eq(
    join_path_for_test(Linux, ["/tmp", "folder", "app"]),
    "/tmp/folder/app",
  )
  assert_eq(
    join_path_for_test(Windows, ["C:", "apps", "tool.exe"]),
    "C:\\apps\\tool.exe",
  )
}

///|
test "wait_until returns false after timeout" {
  assert_false(wait_until_for_test(20, 10, fn() { false }))
}
