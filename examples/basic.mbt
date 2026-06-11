fn main {
  match @replace_self.replace_self("/absolute/path/to/replacement") {
    Ok(_) => println("replacement scheduled")
    Err(err) => println("replacement failed: \{err}")
  }
}
