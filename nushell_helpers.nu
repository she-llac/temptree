def --env temptree [...args: string] {
  let dir = (^temptree ...$args)
  cd $dir
}

def --env rmtree [...args: string] {
  let has_path = ($args | any {|a|
    not ($a starts-with "-") and $a != "--force" and $a != "-f" and $a != "--dry-run"
  })
  let dir = (^rmtree ...$args)
  if not $has_path and ($dir | is-not-empty) {
    cd $dir
  }
}
