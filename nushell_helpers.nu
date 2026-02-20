def --env temptree [...args: string] {
  let dir = (^temptree ...$args)
  cd $dir
}

def --env rmtree [...args: string] {
  let has_path = ($args | any {|a| $a == "--" or not ($a starts-with "-")})
  let dir = (^rmtree ...$args)
  if not $has_path and ($dir | is-not-empty) {
    cd $dir
  }
}
