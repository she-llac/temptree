def --env temptree [...args: string] {
  if ($args | any {|a| $a == "-h" or $a == "--help"}) {
    ^temptree ...$args; return
  }
  let dir = (^temptree ...$args)
  if ($dir | is-not-empty) and ($dir | path type) == "dir" {
    cd $dir
  }
}

def --env rmtree [...args: string] {
  if ($args | any {|a| $a == "-h" or $a == "--help"}) {
    ^rmtree ...$args; return
  }
  let has_path = ($args | any {|a| $a == "--" or not ($a starts-with "-")})
  let dir = (^rmtree ...$args)
  if not $has_path and ($dir | is-not-empty) and ($dir | path type) == "dir" {
    cd $dir
  }
}
