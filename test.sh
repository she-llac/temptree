#!/bin/bash

TEMPTREE="${TEMPTREE:-$(cd "$(dirname "$0")" && pwd)/temptree}"
RMTREE="${RMTREE:-$(cd "$(dirname "$0")" && pwd)/rmtree}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

pass=0
fail=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo -e "  ${GREEN}✓${RESET} $label" >&2
        ((pass++))
    else
        echo -e "  ${RED}✗${RESET} $label" >&2
        echo "    expected: $(echo "$expected" | head -3)" >&2
        echo "    actual:   $(echo "$actual" | head -3)" >&2
        ((fail++))
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF -- "$needle"; then
        echo -e "  ${GREEN}✓${RESET} $label" >&2
        ((pass++))
    else
        echo -e "  ${RED}✗${RESET} $label" >&2
        echo "    expected to contain: $needle" >&2
        echo "    actual: $(echo "$haystack" | head -3)" >&2
        ((fail++))
    fi
}

# Cross-platform helpers (GNU first, BSD fallback)
file_hash() {
    md5sum "$1" 2>/dev/null | cut -d' ' -f1 || md5 -q "$1"
}
file_mode() {
    stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

# Remove a worktree (for test cleanup — does not depend on rmtree)
remove_wt() {
    git -C "$dir" worktree remove --force "$1" >/dev/null 2>&1 || rm -rf "$1"
}

# Track extra temp dirs for cleanup
tmp_dirs=()
mktmp() {
    local d
    d=$(mktemp -d)
    tmp_dirs+=("$d")
    echo "$d"
}

# --- setup ---
export TEMPTREE_FOREST_DIR
TEMPTREE_FOREST_DIR=$(mktemp -d)
dir=$(mktemp -d)

cleanup_all() {
    rm -rf "$dir" "$TEMPTREE_FOREST_DIR" "${tmp_dirs[@]}"
}
trap cleanup_all EXIT

cd "$dir" || exit
dir=$(pwd -P)  # resolve symlinks (macOS /var -> /private/var) for consistent comparisons
git init -q
echo "tracked" > file.txt
mkdir sub
echo "subfile" > sub/deep.txt
git add . && git commit -q -m "initial"

echo "test repo: $dir"
echo "forest dir: $TEMPTREE_FOREST_DIR"
echo


# ===== TEMPTREE TESTS =====

# === Test 1: basic create ===
echo -e "${BOLD}Test 1: basic create${RESET}"
wt=$("$TEMPTREE")
assert_eq "creates a directory" "yes" "$(test -d "$wt" && echo yes || echo no)"
assert_contains "under forest dir" "$TEMPTREE_FOREST_DIR" "$wt"
assert_eq ".git is a file (not a directory)" "yes" "$(test -f "$wt/.git" && echo yes || echo no)"
head_ref=$(git -C "$wt" symbolic-ref HEAD 2>&1) || true
assert_contains "detached HEAD" "not a symbolic ref" "$head_ref"
remove_wt "$wt"
echo

# === Test 2: file copying ===
echo -e "${BOLD}Test 2: file copying${RESET}"
echo "modified" > file.txt
echo "untracked" > extra.txt
echo "secret" > .env
wt=$("$TEMPTREE")
assert_eq "tracked file copied" "modified" "$(cat "$wt/file.txt")"
assert_eq "untracked file copied" "untracked" "$(cat "$wt/extra.txt")"
assert_eq "dotfile copied" "secret" "$(cat "$wt/.env")"
assert_eq "subdirectory copied" "subfile" "$(cat "$wt/sub/deep.txt")"
assert_eq ".git not copied as directory" "no" "$(test -d "$wt/.git" && echo yes || echo no)"
remove_wt "$wt"
echo

# === Test 3: original repo untouched ===
echo -e "${BOLD}Test 3: original repo untouched${RESET}"
index_before=$(git diff --cached --name-status)
worktree_before=$(git diff --name-status)
untracked_before=$(git ls-files --others --exclude-standard | sort)
wt=$("$TEMPTREE")
# Modify something in the worktree
echo "worktree change" > "$wt/file.txt"
rm "$wt/extra.txt"
index_after=$(git diff --cached --name-status)
worktree_after=$(git diff --name-status)
untracked_after=$(git ls-files --others --exclude-standard | sort)
assert_eq "index unchanged" "$index_before" "$index_after"
assert_eq "worktree unchanged" "$worktree_before" "$worktree_after"
assert_eq "untracked unchanged" "$untracked_before" "$untracked_after"
assert_eq "original file not modified" "modified" "$(cat file.txt)"
remove_wt "$wt"
echo

# === Test 4: custom name (-n) ===
echo -e "${BOLD}Test 4: custom name (-n)${RESET}"
wt=$("$TEMPTREE" -n "experiment")
repo_name=$(basename "$(git worktree list --porcelain | head -1 | sed 's/^worktree //')")
assert_contains "name in path" "${repo_name}-experiment" "$wt"
assert_eq "worktree exists" "yes" "$(test -d "$wt" && echo yes || echo no)"
remove_wt "$wt"
echo

# === Test 5: duplicate name does not destroy existing ===
echo -e "${BOLD}Test 5: duplicate name (-n) safe${RESET}"
wt=$("$TEMPTREE" -n "victim")
echo "precious" > "$wt/precious.txt"
dup_output=$("$TEMPTREE" -n "victim" 2>&1)
dup_status=$?
assert_eq "duplicate fails" "1" "$dup_status"
assert_contains "error mentions exists" "already exists" "$dup_output"
assert_eq "original worktree still exists" "yes" "$(test -d "$wt" && echo yes || echo no)"
assert_eq "original content preserved" "precious" "$(cat "$wt/precious.txt")"
remove_wt "$wt"
echo

# === Test 6: custom directory (-d) ===
echo -e "${BOLD}Test 6: custom directory (-d)${RESET}"
custom_dir=$(mktmp)/custom-wt
wt=$("$TEMPTREE" -d "$custom_dir")
assert_eq "created at custom path" "$custom_dir" "$wt"
assert_eq "file copied" "modified" "$(cat "$wt/file.txt")"
remove_wt "$wt"
echo

# === Test 7: -d with pre-existing empty dir ===
echo -e "${BOLD}Test 7: -d with empty dir${RESET}"
empty_dir=$(mktmp)
wt=$("$TEMPTREE" -d "$empty_dir")
assert_eq "created in empty dir" "$empty_dir" "$wt"
assert_eq "file copied" "modified" "$(cat "$wt/file.txt")"
remove_wt "$wt"
echo

# === Test 8: -d with non-empty dir ===
echo -e "${BOLD}Test 8: -d with non-empty dir${RESET}"
nonempty_dir=$(mktmp)
echo "blocker" > "$nonempty_dir/existing.txt"
output=$("$TEMPTREE" -d "$nonempty_dir" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "exists and is not empty" "$output"
echo

# === Test 9: -n and -d conflict ===
echo -e "${BOLD}Test 9: -n and -d conflict${RESET}"
output=$("$TEMPTREE" -n foo -d /tmp/bar 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "cannot be used together" "$output"
# Also test reverse order
output=$("$TEMPTREE" -d /tmp/bar -n foo 2>&1)
status=$?
assert_eq "fails (reverse order)" "1" "$status"
assert_contains "error message (reverse)" "cannot be used together" "$output"
echo

# === Test 10: commits for later tests ===
echo -e "${BOLD}Test 10: setup commits${RESET}"
git add -A && git commit -q -m "second commit"
echo "v3" > file.txt && git add . && git commit -q -m "third commit"
assert_eq "file at v3" "v3" "$(cat file.txt)"
echo

# === Test 12: from subdirectory ===
echo -e "${BOLD}Test 12: from subdirectory${RESET}"
cd "$dir/sub" || exit
wt=$("$TEMPTREE")
assert_eq "creates from subdir" "yes" "$(test -d "$wt" && echo yes || echo no)"
assert_eq "has root file" "v3" "$(cat "$wt/file.txt")"
assert_eq "has subdir file" "subfile" "$(cat "$wt/sub/deep.txt")"
remove_wt "$wt"
cd "$dir" || exit
echo

# === Test 13: from secondary worktree ===
echo -e "${BOLD}Test 13: from secondary worktree${RESET}"
git worktree add -q "$dir/side-wt" --detach HEAD
echo "side change" > "$dir/side-wt/side.txt"
cd "$dir/side-wt" || exit
wt=$("$TEMPTREE")
main_name=$(basename "$(git worktree list --porcelain | head -1 | sed 's/^worktree //')")
assert_contains "uses main repo name" "$main_name" "$(basename "$wt")"
assert_eq "has side file" "side change" "$(cat "$wt/side.txt")"
remove_wt "$wt"
cd "$dir" || exit
git worktree remove --force "$dir/side-wt" >/dev/null 2>&1
echo

# === Test 14: not in git repo ===
echo -e "${BOLD}Test 14: not in git repo${RESET}"
nogit_dir=$(mktmp)
output=$(cd "$nogit_dir" && "$TEMPTREE" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "not inside a git repository" "$output"
echo

# === Test 15: TEMPTREE_FOREST_DIR relative path ===
echo -e "${BOLD}Test 15: relative TEMPTREE_FOREST_DIR${RESET}"
output=$(TEMPTREE_FOREST_DIR="relative/path" "$TEMPTREE" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "absolute path" "$output"
echo

# === Test 16: custom TEMPTREE_FOREST_DIR ===
echo -e "${BOLD}Test 16: custom TEMPTREE_FOREST_DIR${RESET}"
custom_forest=$(mktmp)
wt=$(TEMPTREE_FOREST_DIR="$custom_forest" "$TEMPTREE")
assert_contains "under custom forest" "$custom_forest" "$wt"
assert_eq "worktree exists" "yes" "$(test -d "$wt" && echo yes || echo no)"
remove_wt "$wt"
echo

# === Test 17: --dry-run ===
echo -e "${BOLD}Test 17: temptree --dry-run${RESET}"
dry_output=$("$TEMPTREE" --dry-run 2>&1)
dry_status=$?
assert_eq "exits zero" "0" "$dry_status"
assert_contains "shows forest dir" "$TEMPTREE_FOREST_DIR" "$dry_output"
assert_contains "shows source" "$dir" "$dry_output"
# Nothing actually created
leftover=$(find "$TEMPTREE_FOREST_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_eq "nothing created" "0" "$leftover"
echo

# === Test 18: --dry-run does not create forest dir ===
echo -e "${BOLD}Test 18: --dry-run no side effects${RESET}"
dry_forest=$(mktmp)
rmdir "$dry_forest"  # remove so we can check it doesn't get recreated
TEMPTREE_FOREST_DIR="$dry_forest" "$TEMPTREE" --dry-run 2>/dev/null
assert_eq "forest dir not created" "no" "$(test -d "$dry_forest" && echo yes || echo no)"
echo

# === Test 19: --dry-run with options ===
echo -e "${BOLD}Test 19: --dry-run with options${RESET}"
dry_output=$("$TEMPTREE" --dry-run -n "drytest" 2>&1)
dry_status=$?
assert_eq "exits zero" "0" "$dry_status"
assert_contains "shows name" "drytest" "$dry_output"
echo

# === Test 20: help ===
echo -e "${BOLD}Test 20: temptree help${RESET}"
help_output=$("$TEMPTREE" -h)
help_status=$?
assert_eq "exits zero" "0" "$help_status"
assert_contains "usage line" "Usage: temptree" "$help_output"
assert_contains "documents --dry-run" "dry-run" "$help_output"
help_output2=$("$TEMPTREE" --help)
assert_contains "long flag works" "Usage: temptree" "$help_output2"
echo

# === Test 21: unknown option ===
echo -e "${BOLD}Test 21: temptree unknown option${RESET}"
output=$("$TEMPTREE" --bogus 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "unknown option" "$output"
echo

# === Test 22: unexpected arguments ===
echo -e "${BOLD}Test 22: temptree unexpected args${RESET}"
output=$("$TEMPTREE" somearg 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "unexpected argument" "$output"
echo

# === Test 23: option order independence ===
echo -e "${BOLD}Test 23: option order independence${RESET}"
# -n before --dry-run
dry_output=$("$TEMPTREE" -n "order1" --dry-run 2>&1)
assert_contains "name before dry-run" "order1" "$dry_output"
# --dry-run before -n
dry_output=$("$TEMPTREE" --dry-run -n "order2" 2>&1)
assert_contains "dry-run before name" "order2" "$dry_output"
echo

# === Test 24: symlinks preserved ===
echo -e "${BOLD}Test 24: symlinks${RESET}"
echo "target content" > real.txt
ln -s real.txt link.txt
wt=$("$TEMPTREE")
assert_eq "symlink is a symlink" "yes" "$(test -L "$wt/link.txt" && echo yes || echo no)"
assert_eq "symlink target" "real.txt" "$(readlink "$wt/link.txt")"
assert_eq "symlink content" "target content" "$(cat "$wt/link.txt")"
rm -f real.txt link.txt
remove_wt "$wt"
echo

# === Test 25: binary files ===
echo -e "${BOLD}Test 25: binary files${RESET}"
dd if=/dev/urandom of=binary.bin bs=1024 count=64 2>/dev/null
expected_md5=$(file_hash binary.bin)
wt=$("$TEMPTREE")
actual_md5=$(file_hash "$wt/binary.bin")
assert_eq "binary roundtrip" "$expected_md5" "$actual_md5"
rm -f binary.bin
remove_wt "$wt"
echo

# === Test 26: -m/--message style flag rejected ===
echo -e "${BOLD}Test 26: missing value for -n${RESET}"
output=$("$TEMPTREE" -n 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "--name requires a value" "$output"
output=$("$TEMPTREE" -d 2>&1)
status=$?
assert_eq "-d fails without value" "1" "$status"
assert_contains "-d error" "--dir requires a path" "$output"
echo


# ===== RMTREE TESTS =====

# === Test 27: rmtree by path ===
echo -e "${BOLD}Test 27: rmtree by path${RESET}"
wt=$("$TEMPTREE")
output=$("$RMTREE" "$wt")
assert_eq "no output with path" "" "$output"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 28: rmtree no args (current dir) ===
echo -e "${BOLD}Test 28: rmtree no args${RESET}"
wt=$("$TEMPTREE")
main=$(cd "$wt" && "$RMTREE")
assert_eq "returns main root" "$dir" "$main"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 29: rmtree --force required outside forest ===
echo -e "${BOLD}Test 29: rmtree --force required${RESET}"
custom_dir=$(mktmp)/outside-wt
wt=$("$TEMPTREE" -d "$custom_dir")
output=$("$RMTREE" "$wt" 2>&1)
status=$?
assert_eq "fails without --force" "1" "$status"
assert_contains "error mentions force" "use --force" "$output"
assert_eq "worktree still exists" "yes" "$(test -d "$wt" && echo yes || echo no)"
# Now with --force
"$RMTREE" -f "$wt"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 30: rmtree refuses main worktree ===
echo -e "${BOLD}Test 30: rmtree refuses main worktree${RESET}"
output=$("$RMTREE" -f "$dir" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error mentions main worktree" "main worktree" "$output"
assert_eq "main repo still exists" "yes" "$(test -d "$dir" && echo yes || echo no)"
echo

# === Test 31: rmtree refuses main worktree inside forest ===
echo -e "${BOLD}Test 31: rmtree refuses main worktree in forest${RESET}"
forest_repo="$TEMPTREE_FOREST_DIR/fake-main"
mkdir -p "$forest_repo"
git -C "$forest_repo" init -q
git -C "$forest_repo" commit --allow-empty -q -m "root"
output=$("$RMTREE" "$forest_repo" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error mentions main worktree" "main worktree" "$output"
assert_eq "repo still exists" "yes" "$(test -d "$forest_repo" && echo yes || echo no)"
rm -rf "$forest_repo"
echo

# === Test 32: rmtree non-directory ===
echo -e "${BOLD}Test 32: rmtree non-directory${RESET}"
output=$("$RMTREE" /nonexistent/path 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "not a directory" "$output"
echo

# === Test 33: rmtree non-git directory ===
echo -e "${BOLD}Test 33: rmtree non-git directory${RESET}"
nogit_dir=$(mktmp)
output=$("$RMTREE" -f "$nogit_dir" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "not in a git worktree" "$output"
echo

# === Test 34: rmtree --dry-run ===
echo -e "${BOLD}Test 34: rmtree --dry-run${RESET}"
wt=$("$TEMPTREE")
dry_output=$("$RMTREE" --dry-run "$wt" 2>&1)
dry_status=$?
assert_eq "exits zero" "0" "$dry_status"
assert_contains "shows worktree path" "$wt" "$dry_output"
assert_contains "shows main repo" "$dir" "$dry_output"
assert_eq "worktree NOT removed" "yes" "$(test -d "$wt" && echo yes || echo no)"
remove_wt "$wt"
echo

# === Test 35: TEMPTREE_PRUNE_FOREST ===
echo -e "${BOLD}Test 35: TEMPTREE_PRUNE_FOREST${RESET}"
prune_forest=$(mktmp)
wt=$(TEMPTREE_FOREST_DIR="$prune_forest" "$TEMPTREE")
TEMPTREE_PRUNE_FOREST=0 TEMPTREE_FOREST_DIR="$prune_forest" "$RMTREE" "$wt" >/dev/null
assert_eq "forest preserved with PRUNE=0" "yes" "$(test -d "$prune_forest" && echo yes || echo no)"
wt=$(TEMPTREE_FOREST_DIR="$prune_forest" "$TEMPTREE")
TEMPTREE_PRUNE_FOREST=1 TEMPTREE_FOREST_DIR="$prune_forest" "$RMTREE" "$wt" >/dev/null
assert_eq "forest pruned with PRUNE=1" "no" "$(test -d "$prune_forest" && echo yes || echo no)"
echo

# === Test 36: rmtree help ===
echo -e "${BOLD}Test 36: rmtree help${RESET}"
help_output=$("$RMTREE" -h)
help_status=$?
assert_eq "exits zero" "0" "$help_status"
assert_contains "usage line" "Usage: rmtree" "$help_output"
assert_contains "documents --dry-run" "dry-run" "$help_output"
assert_contains "documents --force" "force" "$help_output"
echo

# === Test 37: rmtree unknown option ===
echo -e "${BOLD}Test 37: rmtree unknown option${RESET}"
output=$("$RMTREE" --bogus 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "unknown option" "$output"
echo

# === Test 38: rmtree too many args ===
echo -e "${BOLD}Test 38: rmtree too many args${RESET}"
output=$("$RMTREE" a b 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "too many arguments" "$output"
echo



# === Test 42: -- separator in temptree ===
echo -e "${BOLD}Test 42: temptree -- separator${RESET}"
wt=$("$TEMPTREE" -n "dashtest" --)
assert_eq "creates with trailing --" "yes" "$(test -d "$wt" && echo yes || echo no)"
assert_contains "name applied with --" "dashtest" "$wt"
remove_wt "$wt"
# -- with arg after it errors
output=$("$TEMPTREE" -- somearg 2>&1)
status=$?
assert_eq "arg after -- rejected" "1" "$status"
assert_contains "error message" "unexpected argument" "$output"
echo

# === Test 43: -- separator in rmtree ===
echo -e "${BOLD}Test 43: rmtree -- separator${RESET}"
wt=$("$TEMPTREE")
"$RMTREE" -- "$wt"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 44: -n with slashes rejected ===
echo -e "${BOLD}Test 44: -n with slashes rejected${RESET}"
output=$("$TEMPTREE" -n "foo/bar" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "must not contain '/'" "$output"
output=$("$TEMPTREE" -n "a/b/c" 2>&1)
status=$?
assert_eq "fails (deeper)" "1" "$status"
echo

# === Test 45: -d with a regular file ===
echo -e "${BOLD}Test 45: -d with regular file${RESET}"
tmpfile=$(mktemp)
output=$("$TEMPTREE" -d "$tmpfile" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "is not a directory" "$output"
rm -f "$tmpfile"
echo

# === Test 46: filenames with spaces ===
echo -e "${BOLD}Test 46: filenames with spaces${RESET}"
echo "spaced" > "$dir/file with spaces.txt"
mkdir -p "$dir/dir with spaces"
echo "deep spaced" > "$dir/dir with spaces/inner file.txt"
wt=$("$TEMPTREE")
assert_eq "spaced file copied" "spaced" "$(cat "$wt/file with spaces.txt")"
assert_eq "spaced dir file copied" "deep spaced" "$(cat "$wt/dir with spaces/inner file.txt")"
rm -rf "$dir/file with spaces.txt" "$dir/dir with spaces"
remove_wt "$wt"
echo

# === Test 47: empty working tree (no files besides .git) ===
echo -e "${BOLD}Test 47: empty working tree${RESET}"
empty_repo=$(mktmp)
git -C "$empty_repo" init -q
git -C "$empty_repo" commit --allow-empty -q -m "empty"
empty_forest=$(mktmp)
wt=$(cd "$empty_repo" && TEMPTREE_FOREST_DIR="$empty_forest" "$TEMPTREE")
assert_eq "creates worktree" "yes" "$(test -d "$wt" && echo yes || echo no)"
# Only .git should exist
wt_files=$(ls -A "$wt")
assert_eq "only .git in worktree" ".git" "$wt_files"
git -C "$empty_repo" worktree remove --force "$wt" 2>/dev/null
echo

# === Test 48: symlink-to-directory preserved ===
echo -e "${BOLD}Test 48: symlink-to-directory${RESET}"
mkdir -p "$dir/realdir"
echo "inside" > "$dir/realdir/inner.txt"
ln -s realdir "$dir/linkdir"
wt=$("$TEMPTREE")
assert_eq "dir symlink is a symlink" "yes" "$(test -L "$wt/linkdir" && echo yes || echo no)"
assert_eq "dir symlink target" "realdir" "$(readlink "$wt/linkdir")"
assert_eq "content via symlink" "inside" "$(cat "$wt/linkdir/inner.txt")"
assert_eq "content via realdir" "inside" "$(cat "$wt/realdir/inner.txt")"
rm -rf "$dir/realdir" "$dir/linkdir"
remove_wt "$wt"
echo

# === Test 49: file permissions preserved ===
echo -e "${BOLD}Test 49: file permissions${RESET}"
echo "exec" > "$dir/script.sh"; chmod 755 "$dir/script.sh"
echo "ro" > "$dir/locked.txt"; chmod 444 "$dir/locked.txt"
echo "priv" > "$dir/secret.txt"; chmod 600 "$dir/secret.txt"
wt=$("$TEMPTREE")
assert_eq "755 preserved" "$(file_mode "$dir/script.sh")" "$(file_mode "$wt/script.sh")"
assert_eq "444 preserved" "$(file_mode "$dir/locked.txt")" "$(file_mode "$wt/locked.txt")"
assert_eq "600 preserved" "$(file_mode "$dir/secret.txt")" "$(file_mode "$wt/secret.txt")"
chmod 644 "$dir/locked.txt" "$wt/locked.txt" 2>/dev/null
rm -f "$dir/script.sh" "$dir/locked.txt" "$dir/secret.txt"
remove_wt "$wt"
echo

# === Test 50: rmtree from subdirectory of worktree ===
echo -e "${BOLD}Test 50: rmtree from subdirectory${RESET}"
mkdir -p "$dir/a/b"
echo "deep" > "$dir/a/b/f.txt"
wt=$("$TEMPTREE")
main=$(cd "$wt/a/b" && "$RMTREE")
assert_eq "returns main root" "$dir" "$main"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
rm -rf "$dir/a"
echo

# === Test 51: nested temptree (temptree from inside a temptree) ===
echo -e "${BOLD}Test 51: nested temptree${RESET}"
wt1=$("$TEMPTREE")
echo "nested" > "$wt1/nested.txt"
wt2=$(cd "$wt1" && "$TEMPTREE")
assert_eq "nested wt created" "yes" "$(test -d "$wt2" && echo yes || echo no)"
assert_eq "nested file copied" "nested" "$(cat "$wt2/nested.txt")"
# Both worktrees share the same main repo name
main_name=$(basename "$(git worktree list --porcelain | head -1 | sed 's/^worktree //')")
assert_contains "wt1 uses main name" "$main_name" "$(basename "$wt1")"
assert_contains "wt2 uses main name" "$main_name" "$(basename "$wt2")"
remove_wt "$wt2"
remove_wt "$wt1"
echo

# === Test 52: -n with spaces ===
echo -e "${BOLD}Test 52: -n with spaces${RESET}"
wt=$("$TEMPTREE" -n "my experiment")
assert_eq "creates worktree" "yes" "$(test -d "$wt" && echo yes || echo no)"
assert_contains "name in path" "my experiment" "$wt"
remove_wt "$wt"
echo

# === Test 53: --dry-run with -d ===
echo -e "${BOLD}Test 53: temptree --dry-run with -d${RESET}"
custom_dry_dir=$(mktmp)/dry-custom
dry_output=$("$TEMPTREE" --dry-run -d "$custom_dry_dir" 2>&1)
dry_status=$?
assert_eq "exits zero" "0" "$dry_status"
assert_contains "shows custom path" "$custom_dry_dir" "$dry_output"
assert_eq "nothing created" "no" "$(test -e "$custom_dry_dir" && echo yes || echo no)"
echo

# === Test 54: rmtree with relative path ===
echo -e "${BOLD}Test 54: rmtree with relative path${RESET}"
wt=$("$TEMPTREE")
wt_name=$(basename "$wt")
cd "$TEMPTREE_FOREST_DIR" && "$RMTREE" "./$wt_name"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
cd "$dir" || exit
echo

# === Test 55: rmtree with --force and no path (current dir outside forest) ===
echo -e "${BOLD}Test 55: rmtree --force no path${RESET}"
outside_dir=$(mktmp)/outside-force-wt
wt=$("$TEMPTREE" -d "$outside_dir")
main=$(cd "$wt" && "$RMTREE" --force)
assert_eq "returns main root" "$dir" "$main"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 56: rmtree -f no path (current dir outside forest) ===
echo -e "${BOLD}Test 56: rmtree -f no path${RESET}"
outside_dir2=$(mktmp)/outside-f-wt
wt=$("$TEMPTREE" -d "$outside_dir2")
main=$(cd "$wt" && "$RMTREE" -f)
assert_eq "returns main root" "$dir" "$main"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 57: bare repository ===
echo -e "${BOLD}Test 57: bare repository${RESET}"
bare_dir=$(mktmp)
rm -rf "$bare_dir"
git init --bare -q "$bare_dir"
output=$(cd "$bare_dir" && "$TEMPTREE" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "not inside a git repository" "$output"
echo



# === Test 59: relative -d path from subdirectory ===
echo -e "${BOLD}Test 59: relative -d from subdirectory${RESET}"
cd "$dir/sub" || exit
wt=$("$TEMPTREE" -d "../rel-wt")
assert_eq "creates worktree" "yes" "$(test -d "$wt" && echo yes || echo no)"
assert_eq "path is absolute" "/" "${wt:0:1}"
assert_eq "file copied" "v3" "$(cat "$wt/file.txt")"
remove_wt "$wt"
cd "$dir" || exit
echo

# === Test 60: TEMPTREE_FOREST_DIR with trailing slash ===
echo -e "${BOLD}Test 60: trailing slash in TEMPTREE_FOREST_DIR${RESET}"
trailing_forest=$(mktmp)
wt=$(TEMPTREE_FOREST_DIR="$trailing_forest/" "$TEMPTREE")
assert_eq "creates worktree" "yes" "$(test -d "$wt" && echo yes || echo no)"
assert_eq "file copied" "v3" "$(cat "$wt/file.txt")"
TEMPTREE_FOREST_DIR="$trailing_forest/" "$RMTREE" "$wt" >/dev/null
echo

# === Test 61: -n with whitespace-only name ===
echo -e "${BOLD}Test 61: -n with whitespace name${RESET}"
wt=$("$TEMPTREE" -n " ")
assert_eq "creates worktree" "yes" "$(test -d "$wt" && echo yes || echo no)"
assert_contains "space in path" " " "$(basename "$wt")"
remove_wt "$wt"
echo

# === Test 62: relative -d with .. components ===
echo -e "${BOLD}Test 62: relative -d with ..${RESET}"
mkdir -p "$dir/deep"
cd "$dir/deep" || exit
wt=$("$TEMPTREE" -d "../../dotdot-wt")
assert_eq "creates worktree" "yes" "$(test -d "$wt" && echo yes || echo no)"
assert_eq "path is absolute" "/" "${wt:0:1}"
remove_wt "$wt"
rmdir "$dir/deep" 2>/dev/null
cd "$dir" || exit
echo

# === Test 63: cleanup on partial failure ===
echo -e "${BOLD}Test 63: cleanup on partial failure${RESET}"
echo "nope" > "$dir/unreadable.txt"
chmod 000 "$dir/unreadable.txt"
fail_forest=$(mktmp)
output=$(TEMPTREE_FOREST_DIR="$fail_forest" "$TEMPTREE" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
leftover=$(find "$fail_forest" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_eq "partial worktree cleaned up" "0" "$leftover"
chmod 644 "$dir/unreadable.txt"
rm -f "$dir/unreadable.txt"
echo

# === Test 64: git worktree add failure ===
echo -e "${BOLD}Test 64: git worktree add failure${RESET}"
fail_repo=$(mktmp)
git -C "$fail_repo" init -q
git -C "$fail_repo" commit --allow-empty -q -m "init"
chmod 555 "$fail_repo/.git"
fail_forest2=$(mktmp)
output=$(cd "$fail_repo" && TEMPTREE_FOREST_DIR="$fail_forest2" "$TEMPTREE" 2>&1)
status=$?
chmod 755 "$fail_repo/.git"
assert_eq "fails" "1" "$status"
assert_contains "error message" "failed to create worktree" "$output"
echo

# === Test 65: random name exhaustion ===
echo -e "${BOLD}Test 65: random name exhaustion${RESET}"
exhaust_forest=$(mktmp)
repo_name_ex=$(basename "$(git worktree list --porcelain | head -1 | sed 's/^worktree //')")
(cd "$exhaust_forest" && mkdir "$repo_name_ex-"{0000..9999})
output=$(TEMPTREE_FOREST_DIR="$exhaust_forest" "$TEMPTREE" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
# All 10000 names occupied, so nothing should have been created
leftover=$(git worktree list --porcelain | grep -c "^worktree $exhaust_forest" || true)
assert_eq "no worktree created" "0" "$leftover"
echo

# === Test 66: rmtree relative TEMPTREE_FOREST_DIR ===
echo -e "${BOLD}Test 66: rmtree relative TEMPTREE_FOREST_DIR${RESET}"
output=$(TEMPTREE_FOREST_DIR="relative/path" "$RMTREE" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "absolute path" "$output"
echo

# === Test 67: rmtree --dry-run without path ===
echo -e "${BOLD}Test 67: rmtree --dry-run without path${RESET}"
wt=$("$TEMPTREE")
dry_output=$(cd "$wt" && "$RMTREE" --dry-run 2>&1)
dry_status=$?
assert_eq "exits zero" "0" "$dry_status"
assert_contains "shows worktree" "$wt" "$dry_output"
assert_contains "shows main repo" "$dir" "$dry_output"
assert_eq "worktree NOT removed" "yes" "$(test -d "$wt" && echo yes || echo no)"
remove_wt "$wt"
echo

# === Test 68: rmtree --dry-run --force ===
echo -e "${BOLD}Test 68: rmtree --dry-run --force${RESET}"
outside_dry=$(mktmp)/outside-dry-wt
wt=$("$TEMPTREE" -d "$outside_dry")
dry_output=$("$RMTREE" --dry-run --force "$wt" 2>&1)
dry_status=$?
assert_eq "exits zero" "0" "$dry_status"
assert_contains "shows worktree" "$wt" "$dry_output"
assert_eq "worktree NOT removed" "yes" "$(test -d "$wt" && echo yes || echo no)"
remove_wt "$wt"
echo

# === Test 69: rmtree --force inside forest ===
echo -e "${BOLD}Test 69: rmtree --force inside forest${RESET}"
wt=$("$TEMPTREE")
output=$("$RMTREE" --force "$wt" 2>&1)
status=$?
assert_eq "exits zero" "0" "$status"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 70: empty string -n and -d ===
echo -e "${BOLD}Test 70: empty string -n and -d${RESET}"
output=$("$TEMPTREE" -n "" 2>&1)
status=$?
assert_eq "-n '' fails" "1" "$status"
assert_contains "-n '' error" "--name requires a value" "$output"
output=$("$TEMPTREE" -d "" 2>&1)
status=$?
assert_eq "-d '' fails" "1" "$status"
assert_contains "-d '' error" "--dir requires a path" "$output"
echo

# === Test 71: gitignored files are copied ===
echo -e "${BOLD}Test 71: gitignored files are copied${RESET}"
echo "*.log" > "$dir/.gitignore"
echo "should be ignored" > "$dir/debug.log"
git -C "$dir" add .gitignore && git -C "$dir" commit -q -m "add gitignore"
wt=$("$TEMPTREE")
assert_eq "ignored file copied" "should be ignored" "$(cat "$wt/debug.log")"
assert_eq ".gitignore copied" "*.log" "$(cat "$wt/.gitignore")"
gi_status=$(git -C "$wt" status --porcelain --ignored debug.log 2>/dev/null)
assert_contains "file is ignored in worktree" "!!" "$gi_status"
rm -f "$dir/.gitignore" "$dir/debug.log"
remove_wt "$wt"
echo

# === Test 72: multiple worktrees unique names ===
echo -e "${BOLD}Test 72: multiple worktrees unique names${RESET}"
multi_forest=$(mktmp)
wt1=$(TEMPTREE_FOREST_DIR="$multi_forest" "$TEMPTREE")
wt2=$(TEMPTREE_FOREST_DIR="$multi_forest" "$TEMPTREE")
wt3=$(TEMPTREE_FOREST_DIR="$multi_forest" "$TEMPTREE")
assert_eq "wt1 exists" "yes" "$(test -d "$wt1" && echo yes || echo no)"
assert_eq "wt2 exists" "yes" "$(test -d "$wt2" && echo yes || echo no)"
assert_eq "wt3 exists" "yes" "$(test -d "$wt3" && echo yes || echo no)"
assert_eq "wt1 != wt2" "yes" "$([[ "$wt1" != "$wt2" ]] && echo yes || echo no)"
assert_eq "wt2 != wt3" "yes" "$([[ "$wt2" != "$wt3" ]] && echo yes || echo no)"
assert_eq "wt1 != wt3" "yes" "$([[ "$wt1" != "$wt3" ]] && echo yes || echo no)"
remove_wt "$wt1"; remove_wt "$wt2"; remove_wt "$wt3"
echo

# === Test 73: -d parent directory doesn't exist ===
echo -e "${BOLD}Test 73: -d parent doesn't exist${RESET}"
parent_base=$(mktmp)
wt=$("$TEMPTREE" -d "$parent_base/nonexistent/wt")
assert_eq "creates with missing parent" "yes" "$(test -d "$wt" && echo yes || echo no)"
assert_eq "file copied" "v3" "$(cat "$wt/file.txt")"
remove_wt "$wt"
echo

# === Test 74: rmtree with symlinked forest dir ===
echo -e "${BOLD}Test 74: rmtree with symlinked forest dir${RESET}"
real_forest=$(mktmp)
link_parent=$(mktmp)
symlink_forest="$link_parent/forest-link"
ln -s "$real_forest" "$symlink_forest"
wt=$(TEMPTREE_FOREST_DIR="$symlink_forest" "$TEMPTREE")
assert_eq "creates worktree" "yes" "$(test -d "$wt" && echo yes || echo no)"
TEMPTREE_FOREST_DIR="$symlink_forest" "$RMTREE" "$wt"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 75: temptree stdout is clean ===
echo -e "${BOLD}Test 75: temptree stdout is clean${RESET}"
output=$("$TEMPTREE")
line_count=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
assert_eq "exactly one line" "1" "$line_count"
assert_eq "output is a directory" "yes" "$(test -d "$output" && echo yes || echo no)"
remove_wt "$output"
echo

# === Test 76: special characters in filenames ===
echo -e "${BOLD}Test 76: special characters in filenames${RESET}"
echo "star" > "$dir/file*.txt"
echo "question" > "$dir/file?.txt"
echo "bracket" > "$dir/file[1].txt"
mkdir -p "$dir/dir with 'quotes'"
echo "quoted" > "$dir/dir with 'quotes'/inner.txt"
wt=$("$TEMPTREE")
assert_eq "glob star copied" "star" "$(cat "$wt/file*.txt")"
assert_eq "glob question copied" "question" "$(cat "$wt/file?.txt")"
assert_eq "glob bracket copied" "bracket" "$(cat "$wt/file[1].txt")"
assert_eq "quoted dir copied" "quoted" "$(cat "$wt/dir with 'quotes'/inner.txt")"
rm -rf "$dir/file*.txt" "$dir/file?.txt" "$dir/file[1].txt" "$dir/dir with 'quotes'"
remove_wt "$wt"
echo

# === Test 77: rmtree with trailing slash ===
echo -e "${BOLD}Test 77: rmtree with trailing slash${RESET}"
wt=$("$TEMPTREE")
output=$("$RMTREE" "$wt/" 2>&1)
status=$?
assert_eq "exits zero" "0" "$status"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 78: shell helper temptree cd ===
echo -e "${BOLD}Test 78: shell helper temptree cd${RESET}"
helper_dir="$(cd "$(dirname "$TEMPTREE")" && pwd)"
helper_cwd=$(
  export PATH="$helper_dir:$PATH"
  source "$helper_dir/shell_helpers.sh"
  export TEMPTREE_FOREST_DIR
  cd "$dir"
  temptree
  pwd
)
assert_contains "cd into worktree" "$TEMPTREE_FOREST_DIR" "$helper_cwd"
assert_eq "cwd is a directory" "yes" "$(test -d "$helper_cwd" && echo yes || echo no)"
remove_wt "$helper_cwd"
echo

# === Test 79: shell helper rmtree cd back ===
echo -e "${BOLD}Test 79: shell helper rmtree cd back${RESET}"
wt=$("$TEMPTREE")
main_cwd=$(
  export PATH="$helper_dir:$PATH"
  source "$helper_dir/shell_helpers.sh"
  export TEMPTREE_FOREST_DIR
  cd "$wt"
  rmtree
  pwd -P
)
assert_eq "cd back to main repo" "$dir" "$main_cwd"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 80: shell helper error propagation ===
echo -e "${BOLD}Test 80: shell helper error propagation${RESET}"
output=$(
  export PATH="$helper_dir:$PATH"
  source "$helper_dir/shell_helpers.sh"
  export TEMPTREE_FOREST_DIR
  cd "$dir"
  temptree -n "foo/bar" 2>/dev/null
  echo "$?"
  pwd -P
)
helper_status=$(echo "$output" | head -1)
helper_cwd=$(echo "$output" | tail -1)
assert_eq "error status propagated" "1" "$helper_status"
assert_eq "cwd unchanged on error" "$dir" "$helper_cwd"
echo

# === Test 81: shell helper rmtree no cd with path ===
echo -e "${BOLD}Test 81: shell helper rmtree no cd with path${RESET}"
wt=$("$TEMPTREE")
result_cwd=$(
  export PATH="$helper_dir:$PATH"
  source "$helper_dir/shell_helpers.sh"
  export TEMPTREE_FOREST_DIR
  cd "$dir"
  rmtree "$wt"
  pwd -P
)
assert_eq "stays in original dir" "$dir" "$result_cwd"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# --- results ---
echo -e "${BOLD}Results: ${GREEN}$pass passed${RESET}, ${RED}$fail failed${RESET}"
exit "$fail"
