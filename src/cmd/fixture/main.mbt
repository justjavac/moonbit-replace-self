///|
/// Writes a fixture report and exits with `code`.
fn write_report_and_exit(
  report_path : String,
  content : String,
  code : Int,
) -> Unit {
  @fs.write_string_to_file(report_path, content) catch {
    _ => ()
  }
  @sys.exit(code)
}

///|
/// Returns CLI arguments excluding the executable name.
fn fixture_args() -> Array[String] {
  let args = @env.args()
  if args.length() <= 1 {
    []
  } else {
    args[1:].to_array()
  }
}

///|
/// Runs the fixture command requested by the integration tests.
fn main {
  let args = fixture_args()
  if args.length() < 2 {
    @sys.exit(2)
  }

  let command = args[0]
  let report_path = args[args.length() - 1]

  match command {
    "replace" => {
      if args.length() != 3 {
        @sys.exit(2)
      }
      match @replace_self.replace_self(args[1]) {
        Ok(_) => write_report_and_exit(report_path, "replace scheduled", 0)
        Err(error) => write_report_and_exit(report_path, error.to_string(), 1)
      }
    }
    "delete" => {
      if args.length() != 2 {
        @sys.exit(2)
      }
      match @replace_self.delete_self() {
        Ok(_) => write_report_and_exit(report_path, "delete scheduled", 0)
        Err(error) => write_report_and_exit(report_path, error.to_string(), 1)
      }
    }
    _ => @sys.exit(2)
  }
}
