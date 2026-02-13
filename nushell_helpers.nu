def --env temptree [...args: string] {
  let dir = (^temptree ...$args)
  cd $dir
}

def --env rmtree [...args: string] {
  let dir = (^rmtree ...$args)
  if ($args | is-empty) {
    cd $dir
  }
}
