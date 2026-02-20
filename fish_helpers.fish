function temptree
  set -l dir (command temptree $argv); or return
  test -d "$dir" && cd $dir
end

function rmtree
  set -l has_path false
  for arg in $argv
    switch $arg
      case -f --force --dry-run
        # flag, not a path
      case --
        set has_path true
        break
      case '-*'
        # unknown flag, let rmtree handle it
      case '*'
        set has_path true
        break
    end
  end
  set -l dir (command rmtree $argv); or return
  if test "$has_path" = false -a -d "$dir"
    cd $dir
  end
end
