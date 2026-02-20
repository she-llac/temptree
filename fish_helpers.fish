function temptree
  set -l dir (command temptree $argv); or return
  cd $dir; or return
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
  if test "$has_path" = false
    cd $dir; or return
  end
end
