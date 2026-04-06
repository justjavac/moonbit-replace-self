///|
test "replace_self rejects empty public paths" {
  match @replace_self.replace_self("   ") {
    Err(EmptyReplacementPath) => ()
    Err(_) => panic()
    Ok(_) => panic()
  }
}

///|
test "replace_self rejects relative public paths" {
  match @replace_self.replace_self("./next") {
    Err(RelativeReplacementPath(path)) => assert_eq(path, "./next")
    Err(_) => panic()
    Ok(_) => panic()
  }
}
