function temptree
  set -l dir (command temptree $argv); or return
  cd $dir; or return
end

function rmtree
  set -l dir (command rmtree $argv); or return
  if test (count $argv) -eq 0
    cd $dir; or return
  end
end
