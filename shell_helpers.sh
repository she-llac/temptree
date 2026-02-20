# shellcheck shell=bash
temptree() {
  local dir
  dir="$(command temptree "$@")" || return
  builtin cd "$dir" || return
}

rmtree() {
  local dir has_path=false arg
  for arg in "$@"; do
    case "$arg" in
      -f|--force|--dry-run) ;;
      --) has_path=true; break ;;
      -*) ;;
      *) has_path=true; break ;;
    esac
  done
  dir="$(command rmtree "$@")" || return
  if [[ "$has_path" == false ]]; then
    builtin cd "$dir" || return
  fi
}
