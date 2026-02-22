# shellcheck shell=bash
temptree() {
  case "$*" in *-h*|*--help*) command temptree "$@"; return ;; esac
  local dir
  dir="$(command temptree "$@")" || return
  [[ -d "$dir" ]] && builtin cd "$dir"
}

rmtree() {
  case "$*" in *-h*|*--help*) command rmtree "$@"; return ;; esac
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
  if [[ "$has_path" == false && -d "$dir" ]]; then
    builtin cd "$dir"
  fi
}
