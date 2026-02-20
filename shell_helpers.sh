# shellcheck shell=bash
temptree() {
  local dir
  dir="$(command temptree "$@")" || return
  builtin cd "$dir" || return
}

rmtree() {
  local dir
  dir="$(command rmtree "$@")" || return
  if [[ "$#" -eq 0 ]]; then
    builtin cd "$dir" || return
  fi
}
