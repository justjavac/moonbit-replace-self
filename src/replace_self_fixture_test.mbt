///|
/// Runs an external process and returns its exit code.
#borrow(executable, arguments)
extern "C" fn run_process_ffi(executable : Bytes, arguments : Bytes) -> Int = "mb_replace_self_run_process"

///|
/// Sleeps for at least `milliseconds`.
extern "C" fn sleep_millis_ffi(milliseconds : Int) -> Unit = "mb_replace_self_sleep_millis"

///|
/// Returns the native platform code for the host.
extern "C" fn platform_code_for_test() -> Int = "mb_replace_self_platform_code"

///|
/// Returns whether the current host is Windows.
fn is_windows_host() -> Bool {
  platform_code_for_test() == 1
}

///|
/// Joins path segments with the platform separator.
fn join_path_for_fixture(parts : Array[String]) -> String {
  if is_windows_host() {
    parts.join("\\")
  } else {
    parts.join("/")
  }
}

///|
/// Returns the current working directory or panics in tests.
fn current_dir_or_panic() -> String {
  match @env.current_dir() {
    Some(path) => path
    None => panic()
  }
}

///|
/// Returns the current `moon` executable path or panics.
fn moon_executable_or_panic() -> String {
  let executable = if is_windows_host() { "moon.exe" } else { "moon" }
  match @env.get_env_var("MOON_HOME") {
    Some(home) => join_path_for_fixture([home, "bin", executable])
    None => executable
  }
}

///|
/// Creates a unique temporary test directory name.
fn make_test_directory_name(prefix : String) -> String {
  "\{prefix}-\{@env.now().to_int()}"
}

///|
/// Reads a UTF-8 text file and returns `None` when missing.
fn read_optional_text_file(path : String) -> String? {
  Some(@fs.read_file_to_string(path)) catch {
    _ => None
  }
}

///|
/// Creates a directory and panics on failure.
fn create_dir_or_panic(path : String) -> Unit {
  @fs.create_dir(path) catch {
    _ => panic()
  }
}

///|
/// Removes a file when it exists.
fn remove_file_if_exists(path : String) -> Unit {
  try {
    if @fs.path_exists(path) {
      @fs.remove_file(path)
    }
  } catch {
    _ => ()
  }
}

///|
/// Removes a directory tree recursively.
fn remove_tree_if_exists(path : String) -> Unit {
  try {
    if !@fs.path_exists(path) {
      return
    }
    if @fs.is_dir(path) {
      for entry in @fs.read_dir(path) {
        remove_tree_if_exists(join_path_for_fixture([path, entry]))
      }
      @fs.remove_dir(path)
    } else {
      @fs.remove_file(path)
    }
  } catch {
    _ => ()
  }
}

///|
/// Copies a file by reading and writing its bytes.
fn copy_file_or_panic(source : String, destination : String) -> Unit {
  @fs.write_bytes_to_file(destination, @fs.read_file_to_bytes(source)) catch {
    _ => panic()
  }
}

///|
/// Appends `suffix` to a binary file.
fn append_bytes_to_file_or_panic(path : String, suffix : Bytes) -> Unit {
  try {
    let contents = @fs.read_file_to_bytes(path)
    let merged = contents.to_array()
    for value in suffix {
      merged.push(value)
    }
    @fs.write_bytes_to_file(path, Bytes::from_array(merged))
  } catch {
    _ => panic()
  }
}

///|
/// Copies a source file into the temporary fixture project.
fn copy_project_file_or_panic(
  source_root : String,
  destination_root : String,
  relative_parts : Array[String],
) -> Unit {
  let relative_path = join_path_for_fixture(relative_parts)
  let source = join_path_for_fixture([source_root, relative_path])
  let destination = join_path_for_fixture([destination_root, relative_path])
  copy_file_or_panic(source, destination)
}

///|
/// Copies the minimal source set required to build `cmd/fixture`.
fn copy_fixture_project_or_panic(
  source_root : String,
  destination_root : String,
) -> Unit {
  create_dir_or_panic(destination_root)
  create_dir_or_panic(join_path_for_fixture([destination_root, "src"]))
  create_dir_or_panic(join_path_for_fixture([destination_root, "src", "cmd"]))
  create_dir_or_panic(
    join_path_for_fixture([destination_root, "src", "cmd", "fixture"]),
  )

  copy_project_file_or_panic(source_root, destination_root, ["moon.mod.json"])
  copy_project_file_or_panic(source_root, destination_root, ["src", "moon.pkg"])
  copy_project_file_or_panic(source_root, destination_root, [
    "src", "errors.mbt",
  ])
  copy_project_file_or_panic(source_root, destination_root, ["src", "ffi.mbt"])
  copy_project_file_or_panic(source_root, destination_root, [
    "src", "platform.mbt",
  ])
  copy_project_file_or_panic(source_root, destination_root, [
    "src", "replace_self.mbt",
  ])
  copy_project_file_or_panic(source_root, destination_root, [
    "src", "validation.mbt",
  ])
  copy_project_file_or_panic(source_root, destination_root, [
    "src", "replace_self_native.c",
  ])
  copy_project_file_or_panic(source_root, destination_root, [
    "src", "cmd", "fixture", "moon.pkg",
  ])
  copy_project_file_or_panic(source_root, destination_root, [
    "src", "cmd", "fixture", "main.mbt",
  ])
}

///|
/// Runs a child process and panics when spawning fails.
fn run_process_or_panic(executable : String, arguments : Array[String]) -> Int {
  let status = run_process_ffi(
    @utf8.encode(executable),
    @utf8.encode(arguments.join("\n")),
  )
  if status < 0 {
    panic()
  }
  status
}

///|
/// Polls until `predicate` succeeds or the timeout elapses.
fn wait_until(
  timeout_millis : Int,
  interval_millis : Int,
  predicate : () -> Bool,
) -> Bool {
  let mut waited = 0
  while waited <= timeout_millis {
    if predicate() {
      return true
    }
    sleep_millis_ffi(interval_millis)
    waited += interval_millis
  }
  false
}

///|
/// Returns whether `path` exists and is a directory.
fn is_dir_or_false(path : String) -> Bool {
  @fs.is_dir(path) catch {
    _ => false
  }
}

///|
/// Lists a directory or returns an empty array on failure.
fn read_dir_or_empty(path : String) -> Array[String] {
  @fs.read_dir(path) catch {
    _ => []
  }
}

///|
/// Returns the first existing regular file from the candidate paths.
fn first_existing_file(paths : Array[String]) -> String? {
  for path in paths {
    if @fs.path_exists(path) && !is_dir_or_false(path) {
      return Some(path)
    }
  }
  None
}

///|
/// Recursively searches for the built fixture executable under `root`.
fn find_fixture_executable(root : String, executable_name : String) -> String? {
  if !@fs.path_exists(root) || !is_dir_or_false(root) {
    return None
  }
  for entry in read_dir_or_empty(root) {
    let path = join_path_for_fixture([root, entry])
    if is_dir_or_false(path) {
      match find_fixture_executable(path, executable_name) {
        Some(found) => return Some(found)
        None => ()
      }
    } else if entry == executable_name {
      return Some(path)
    }
  }
  None
}

///|
/// Prints fixture-related paths under the temporary project for debugging.
fn log_fixture_search(root : String, executable_name : String) -> Unit {
  println("fixture lookup root: \{root}")
  println("expected executable name: \{executable_name}")
  log_fixture_search_walk(root, executable_name, 0, 8)
}

///|
/// Recursively prints matching fixture-related paths for debugging.
fn log_fixture_search_walk(
  root : String,
  executable_name : String,
  depth : Int,
  max_depth : Int,
) -> Unit {
  if depth > max_depth || !@fs.path_exists(root) || !is_dir_or_false(root) {
    return
  }
  for entry in read_dir_or_empty(root) {
    let path = join_path_for_fixture([root, entry])
    if entry.contains("fixture") || entry == executable_name {
      let kind = if is_dir_or_false(path) { "dir" } else { "file" }
      println("fixture search hit (\{kind}): \{path}")
    }
    if is_dir_or_false(path) {
      log_fixture_search_walk(path, executable_name, depth + 1, max_depth)
    }
  }
}

///|
/// Returns possible fixture executable file names for the current host.
fn fixture_executable_names() -> Array[String] {
  if is_windows_host() {
    ["fixture.exe", "fixture"]
  } else {
    ["fixture", "fixture.exe"]
  }
}

///|
/// Returns the built fixture executable path.
fn built_fixture_executable(project_root : String) -> String {
  let executable_names = fixture_executable_names()
  let executable_name = executable_names[0]
  let debug_root = join_path_for_fixture([
    project_root, "_build", "native", "debug",
  ])
  let candidates = []
  for name in executable_names {
    candidates.push(
      join_path_for_fixture([debug_root, "build", "cmd", "fixture", name]),
    )
    candidates.push(
      join_path_for_fixture([debug_root, "test", "cmd", "fixture", name]),
    )
  }
  match first_existing_file(candidates) {
    Some(path) => path
    None => {
      for name in executable_names {
        match find_fixture_executable(debug_root, name) {
          Some(path) => return path
          None => ()
        }
        match find_fixture_executable(project_root, name) {
          Some(path) => return path
          None => ()
        }
      }
      for candidate in candidates {
        let exists = @fs.path_exists(candidate)
        let kind = if is_dir_or_false(candidate) { "dir" } else { "file" }
        println("fixture candidate (\{kind}) exists=\{exists}: \{candidate}")
      }
      log_fixture_search(project_root, executable_name)
      candidates[0]
    }
  }
}

///|
/// Builds the fixture executable in an isolated temporary project copy.
fn build_fixture_executable(workspace : String) -> String {
  let source_root = current_dir_or_panic()
  let project_root = join_path_for_fixture([workspace, "project"])
  copy_fixture_project_or_panic(source_root, project_root)
  if run_process_or_panic(moon_executable_or_panic(), [
      "-C", project_root, "build", "src/cmd/fixture", "--target", "native",
    ]) !=
    0 {
    panic()
  }
  let executable = built_fixture_executable(project_root)
  if !@fs.path_exists(executable) {
    panic()
  }
  executable
}

///|
/// Creates a dedicated integration-test workspace.
fn make_fixture_workspace() -> String {
  let root = current_dir_or_panic()
  let temp_root = join_path_for_fixture([root, ".test-tmp"])
  let path = join_path_for_fixture([
    temp_root,
    make_test_directory_name("replace-self"),
  ])
  if !@fs.path_exists(temp_root) {
    create_dir_or_panic(temp_root)
  }
  create_dir_or_panic(path)
  path
}

///|
/// Creates a replacement copy with a marker suffix.
fn prepare_replacement_copy(
  fixture_executable : String,
  workspace : String,
) -> (String, Bytes) {
  let replacement_name = if is_windows_host() {
    "fixture-new.exe"
  } else {
    "fixture-new"
  }
  let replacement = join_path_for_fixture([workspace, replacement_name])
  let marker = @utf8.encode("marker:\{workspace}")
  copy_file_or_panic(fixture_executable, replacement)
  append_bytes_to_file_or_panic(replacement, marker)
  (replacement, marker)
}

///|
/// Reads the trailing bytes of a file.
fn read_file_tail(path : String, length : Int) -> Bytes {
  let contents = @fs.read_file_to_bytes(path) catch { _ => panic() }
  let bytes = contents.to_array()
  if bytes.length() < length {
    return Bytes::from_array([])
  }
  let start = bytes.length() - length
  Bytes::from_array(bytes[start:])
}

///|
/// Parses the report file written by the fixture process.
fn read_report(report_path : String) -> String {
  match read_optional_text_file(report_path) {
    Some(contents) => contents
    None => panic()
  }
}

///|
/// Runs the copied fixture executable.
fn run_fixture(target_path : String, arguments : Array[String]) -> Unit {
  if run_process_or_panic(target_path, arguments) != 0 {
    panic()
  }
}

///|
test "replace_self replaces a copied fixture executable" {
  let workspace = make_fixture_workspace()
  let fixture_executable = build_fixture_executable(workspace)
  let target = join_path_for_fixture([
    workspace,
    if is_windows_host() {
      "fixture.exe"
    } else {
      "fixture"
    },
  ])
  let report = join_path_for_fixture([workspace, "replace-report.txt"])
  let (replacement, marker) = prepare_replacement_copy(
    fixture_executable, workspace,
  )
  copy_file_or_panic(fixture_executable, target)

  run_fixture(target, ["replace", replacement, report])

  let replacement_completed = wait_until(8000, 100, fn() {
    @fs.path_exists(target) && read_file_tail(target, marker.length()) == marker
  })
  assert_true(replacement_completed)
  assert_eq(read_report(report), "replace scheduled")

  remove_tree_if_exists(workspace)
}

///|
test "delete_self removes a copied fixture executable" {
  let workspace = make_fixture_workspace()
  let fixture_executable = build_fixture_executable(workspace)
  let target = join_path_for_fixture([
    workspace,
    if is_windows_host() {
      "fixture.exe"
    } else {
      "fixture"
    },
  ])
  let report = join_path_for_fixture([workspace, "delete-report.txt"])
  copy_file_or_panic(fixture_executable, target)

  run_fixture(target, ["delete", report])

  let deletion_completed = wait_until(8000, 100, fn() {
    !@fs.path_exists(target)
  })
  assert_true(deletion_completed)
  assert_eq(read_report(report), "delete scheduled")

  remove_file_if_exists(report)
  remove_tree_if_exists(workspace)
}
