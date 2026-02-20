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

# Remove a worktree (for test cleanup — does not depend on rmtree)
remove_wt() {
    git -C "$dir" worktree remove --force "$1" >/dev/null 2>&1 || rm -rf "$1"
}

# --- setup ---
export TEMPTREE_FOREST_DIR
TEMPTREE_FOREST_DIR=$(mktemp -d)
dir=$(mktemp -d)
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
custom_dir=$(mktemp -d)/custom-wt
wt=$("$TEMPTREE" -d "$custom_dir")
assert_eq "created at custom path" "$custom_dir" "$wt"
assert_eq "file copied" "modified" "$(cat "$wt/file.txt")"
remove_wt "$wt"
echo

# === Test 7: -d with pre-existing empty dir ===
echo -e "${BOLD}Test 7: -d with empty dir${RESET}"
empty_dir=$(mktemp -d)
wt=$("$TEMPTREE" -d "$empty_dir")
assert_eq "created in empty dir" "$empty_dir" "$wt"
assert_eq "file copied" "modified" "$(cat "$wt/file.txt")"
remove_wt "$wt"
echo

# === Test 8: -d with non-empty dir ===
echo -e "${BOLD}Test 8: -d with non-empty dir${RESET}"
nonempty_dir=$(mktemp -d)
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

# === Test 10: ref argument ===
echo -e "${BOLD}Test 10: ref argument${RESET}"
git add -A && git commit -q -m "second commit"
echo "v3" > file.txt && git add . && git commit -q -m "third commit"
wt=$("$TEMPTREE" HEAD~1)
wt_commit=$(git -C "$wt" rev-parse HEAD)
expected_commit=$(git rev-parse HEAD~1)
assert_eq "worktree at correct ref" "$expected_commit" "$wt_commit"
# Files come from current working tree, not the ref
assert_eq "file content from worktree (not ref)" "v3" "$(cat "$wt/file.txt")"
remove_wt "$wt"
echo

# === Test 11: invalid ref ===
echo -e "${BOLD}Test 11: invalid ref${RESET}"
output=$("$TEMPTREE" nonexistent-branch 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error mentions ref" "valid ref" "$output"
# No leftover worktree in forest
leftover=$(find "$TEMPTREE_FOREST_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_eq "no leftover dirs" "0" "$leftover"
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
nogit_dir=$(mktemp -d)
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
custom_forest=$(mktemp -d)
wt=$(TEMPTREE_FOREST_DIR="$custom_forest" "$TEMPTREE")
assert_contains "under custom forest" "$custom_forest" "$wt"
assert_eq "worktree exists" "yes" "$(test -d "$wt" && echo yes || echo no)"
remove_wt "$wt"
rmdir "$custom_forest" 2>/dev/null || true
echo

# === Test 17: --dry-run ===
echo -e "${BOLD}Test 17: temptree --dry-run${RESET}"
dry_output=$("$TEMPTREE" --dry-run 2>&1)
dry_status=$?
assert_eq "exits zero" "0" "$dry_status"
assert_contains "shows forest dir" "$TEMPTREE_FOREST_DIR" "$dry_output"
assert_contains "shows ref" "HEAD" "$dry_output"
assert_contains "shows source" "$dir" "$dry_output"
# Nothing actually created
leftover=$(find "$TEMPTREE_FOREST_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_eq "nothing created" "0" "$leftover"
echo

# === Test 18: --dry-run with options ===
echo -e "${BOLD}Test 18: --dry-run with options${RESET}"
dry_output=$("$TEMPTREE" --dry-run -n "drytest" HEAD~1 2>&1)
dry_status=$?
assert_eq "exits zero" "0" "$dry_status"
assert_contains "shows name" "drytest" "$dry_output"
assert_contains "shows ref" "HEAD~1" "$dry_output"
echo

# === Test 19: help ===
echo -e "${BOLD}Test 19: temptree help${RESET}"
help_output=$("$TEMPTREE" -h)
help_status=$?
assert_eq "exits zero" "0" "$help_status"
assert_contains "usage line" "Usage: temptree" "$help_output"
assert_contains "documents --dry-run" "dry-run" "$help_output"
help_output2=$("$TEMPTREE" --help)
assert_contains "long flag works" "Usage: temptree" "$help_output2"
echo

# === Test 20: unknown option ===
echo -e "${BOLD}Test 20: temptree unknown option${RESET}"
output=$("$TEMPTREE" --bogus 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "unknown option" "$output"
echo

# === Test 21: too many arguments ===
echo -e "${BOLD}Test 21: temptree too many args${RESET}"
output=$("$TEMPTREE" a b c 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "too many arguments" "$output"
echo

# === Test 22: option order independence ===
echo -e "${BOLD}Test 22: option order independence${RESET}"
# -n after ref
wt=$("$TEMPTREE" HEAD -n "ordertest")
assert_contains "name applied" "ordertest" "$wt"
remove_wt "$wt"
# --dry-run before -n
dry_output=$("$TEMPTREE" --dry-run -n "order2" 2>&1)
assert_contains "dry-run works" "order2" "$dry_output"
echo

# === Test 23: symlinks preserved ===
echo -e "${BOLD}Test 23: symlinks${RESET}"
echo "target content" > real.txt
ln -s real.txt link.txt
wt=$("$TEMPTREE")
assert_eq "symlink is a symlink" "yes" "$(test -L "$wt/link.txt" && echo yes || echo no)"
assert_eq "symlink target" "real.txt" "$(readlink "$wt/link.txt")"
assert_eq "symlink content" "target content" "$(cat "$wt/link.txt")"
rm -f real.txt link.txt
remove_wt "$wt"
echo

# === Test 24: binary files ===
echo -e "${BOLD}Test 24: binary files${RESET}"
dd if=/dev/urandom of=binary.bin bs=1024 count=64 2>/dev/null
expected_md5=$(md5 -q binary.bin)
wt=$("$TEMPTREE")
actual_md5=$(md5 -q "$wt/binary.bin")
assert_eq "binary roundtrip" "$expected_md5" "$actual_md5"
rm -f binary.bin
remove_wt "$wt"
echo

# === Test 25: -m/--message style flag rejected ===
echo -e "${BOLD}Test 25: missing value for -n${RESET}"
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

# === Test 26: rmtree by path ===
echo -e "${BOLD}Test 26: rmtree by path${RESET}"
wt=$("$TEMPTREE")
main=$("$RMTREE" "$wt")
assert_eq "returns main root" "$dir" "$main"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 27: rmtree no args (current dir) ===
echo -e "${BOLD}Test 27: rmtree no args${RESET}"
wt=$("$TEMPTREE")
main=$(cd "$wt" && "$RMTREE")
assert_eq "returns main root" "$dir" "$main"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 28: rmtree --force required outside forest ===
echo -e "${BOLD}Test 28: rmtree --force required${RESET}"
custom_dir=$(mktemp -d)/outside-wt
wt=$("$TEMPTREE" -d "$custom_dir")
output=$("$RMTREE" "$wt" 2>&1)
status=$?
assert_eq "fails without --force" "1" "$status"
assert_contains "error mentions force" "use --force" "$output"
assert_eq "worktree still exists" "yes" "$(test -d "$wt" && echo yes || echo no)"
# Now with --force
main=$("$RMTREE" -f "$wt")
assert_eq "succeeds with --force" "$dir" "$main"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 29: rmtree refuses main worktree ===
echo -e "${BOLD}Test 29: rmtree refuses main worktree${RESET}"
output=$("$RMTREE" -f "$dir" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error mentions main worktree" "main worktree" "$output"
assert_eq "main repo still exists" "yes" "$(test -d "$dir" && echo yes || echo no)"
echo

# === Test 30: rmtree refuses main worktree inside forest ===
echo -e "${BOLD}Test 30: rmtree refuses main worktree in forest${RESET}"
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

# === Test 31: rmtree non-directory ===
echo -e "${BOLD}Test 31: rmtree non-directory${RESET}"
output=$("$RMTREE" /nonexistent/path 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "not a directory" "$output"
echo

# === Test 32: rmtree non-git directory ===
echo -e "${BOLD}Test 32: rmtree non-git directory${RESET}"
nogit_dir=$(mktemp -d)
output=$("$RMTREE" -f "$nogit_dir" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "not in a git worktree" "$output"
echo

# === Test 33: rmtree --dry-run ===
echo -e "${BOLD}Test 33: rmtree --dry-run${RESET}"
wt=$("$TEMPTREE")
dry_output=$("$RMTREE" --dry-run "$wt" 2>&1)
dry_status=$?
assert_eq "exits zero" "0" "$dry_status"
assert_contains "shows worktree path" "$wt" "$dry_output"
assert_contains "shows main repo" "$dir" "$dry_output"
assert_eq "worktree NOT removed" "yes" "$(test -d "$wt" && echo yes || echo no)"
remove_wt "$wt"
echo

# === Test 34: TEMPTREE_PRUNE_FOREST ===
echo -e "${BOLD}Test 34: TEMPTREE_PRUNE_FOREST${RESET}"
prune_forest=$(mktemp -d)
wt=$(TEMPTREE_FOREST_DIR="$prune_forest" "$TEMPTREE")
TEMPTREE_PRUNE_FOREST=0 TEMPTREE_FOREST_DIR="$prune_forest" "$RMTREE" "$wt" >/dev/null
assert_eq "forest preserved with PRUNE=0" "yes" "$(test -d "$prune_forest" && echo yes || echo no)"
wt=$(TEMPTREE_FOREST_DIR="$prune_forest" "$TEMPTREE")
TEMPTREE_PRUNE_FOREST=1 TEMPTREE_FOREST_DIR="$prune_forest" "$RMTREE" "$wt" >/dev/null
assert_eq "forest pruned with PRUNE=1" "no" "$(test -d "$prune_forest" && echo yes || echo no)"
echo

# === Test 35: rmtree help ===
echo -e "${BOLD}Test 35: rmtree help${RESET}"
help_output=$("$RMTREE" -h)
help_status=$?
assert_eq "exits zero" "0" "$help_status"
assert_contains "usage line" "Usage: rmtree" "$help_output"
assert_contains "documents --dry-run" "dry-run" "$help_output"
assert_contains "documents --force" "force" "$help_output"
echo

# === Test 36: rmtree unknown option ===
echo -e "${BOLD}Test 36: rmtree unknown option${RESET}"
output=$("$RMTREE" --bogus 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "unknown option" "$output"
echo

# === Test 37: rmtree too many args ===
echo -e "${BOLD}Test 37: rmtree too many args${RESET}"
output=$("$RMTREE" a b 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "too many arguments" "$output"
echo

# === Test 38: cleanup on failed copy does not leak worktree ===
echo -e "${BOLD}Test 38: cleanup on failure${RESET}"
# Make repo_root temporarily unreadable to break the copy step
# (We can't easily do this without root, so test the invalid-ref case instead,
# which verifies the cleanup trap doesn't leave partial state)
before=$(git worktree list --porcelain | grep -c '^worktree')
"$TEMPTREE" nonexistent-ref 2>/dev/null || true
after=$(git worktree list --porcelain | grep -c '^worktree')
assert_eq "no stale worktree entries" "$before" "$after"
echo

# === Test 39: positional dir form (backward compat) ===
echo -e "${BOLD}Test 39: positional dir form${RESET}"
pos_dir=$(mktemp -d)/pos-wt
wt=$("$TEMPTREE" HEAD "$pos_dir")
assert_eq "created at positional path" "$pos_dir" "$wt"
assert_eq "file copied" "v3" "$(cat "$wt/file.txt")"
remove_wt "$wt"
echo

# === Test 40: positional dir conflicts with -d ===
echo -e "${BOLD}Test 40: positional dir + -d conflict${RESET}"
output=$("$TEMPTREE" -d /tmp/a HEAD /tmp/b 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "cannot specify directory both" "$output"
echo

# === Test 41: -- separator in temptree ===
echo -e "${BOLD}Test 41: temptree -- separator${RESET}"
wt=$("$TEMPTREE" -- HEAD)
assert_eq "creates with -- before ref" "yes" "$(test -d "$wt" && echo yes || echo no)"
assert_eq "file copied" "v3" "$(cat "$wt/file.txt")"
remove_wt "$wt"
# -- with no ref defaults to HEAD
wt=$("$TEMPTREE" -n "dashtest" --)
assert_contains "name applied with --" "dashtest" "$wt"
remove_wt "$wt"
echo

# === Test 42: -- separator in rmtree ===
echo -e "${BOLD}Test 42: rmtree -- separator${RESET}"
wt=$("$TEMPTREE")
main=$("$RMTREE" -- "$wt")
assert_eq "returns main root" "$dir" "$main"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 43: -n with slashes rejected ===
echo -e "${BOLD}Test 43: -n with slashes rejected${RESET}"
output=$("$TEMPTREE" -n "foo/bar" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "must not contain '/'" "$output"
output=$("$TEMPTREE" -n "a/b/c" 2>&1)
status=$?
assert_eq "fails (deeper)" "1" "$status"
echo

# === Test 44: -d with a regular file ===
echo -e "${BOLD}Test 44: -d with regular file${RESET}"
tmpfile=$(mktemp)
output=$("$TEMPTREE" -d "$tmpfile" 2>&1)
status=$?
assert_eq "fails" "1" "$status"
assert_contains "error message" "is not a directory" "$output"
rm -f "$tmpfile"
echo

# === Test 45: filenames with spaces ===
echo -e "${BOLD}Test 45: filenames with spaces${RESET}"
echo "spaced" > "$dir/file with spaces.txt"
mkdir -p "$dir/dir with spaces"
echo "deep spaced" > "$dir/dir with spaces/inner file.txt"
wt=$("$TEMPTREE")
assert_eq "spaced file copied" "spaced" "$(cat "$wt/file with spaces.txt")"
assert_eq "spaced dir file copied" "deep spaced" "$(cat "$wt/dir with spaces/inner file.txt")"
rm -rf "$dir/file with spaces.txt" "$dir/dir with spaces"
remove_wt "$wt"
echo

# === Test 46: empty working tree (no files besides .git) ===
echo -e "${BOLD}Test 46: empty working tree${RESET}"
empty_repo=$(mktemp -d)
git -C "$empty_repo" init -q
git -C "$empty_repo" commit --allow-empty -q -m "empty"
empty_forest=$(mktemp -d)
wt=$(cd "$empty_repo" && TEMPTREE_FOREST_DIR="$empty_forest" "$TEMPTREE")
assert_eq "creates worktree" "yes" "$(test -d "$wt" && echo yes || echo no)"
# Only .git should exist
wt_files=$(ls -A "$wt")
assert_eq "only .git in worktree" ".git" "$wt_files"
git -C "$empty_repo" worktree remove --force "$wt" 2>/dev/null
rm -rf "$empty_repo" "$empty_forest"
echo

# === Test 47: symlink-to-directory preserved ===
echo -e "${BOLD}Test 47: symlink-to-directory${RESET}"
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

# === Test 48: file permissions preserved ===
echo -e "${BOLD}Test 48: file permissions${RESET}"
echo "exec" > "$dir/script.sh"; chmod 755 "$dir/script.sh"
echo "ro" > "$dir/locked.txt"; chmod 444 "$dir/locked.txt"
echo "priv" > "$dir/secret.txt"; chmod 600 "$dir/secret.txt"
wt=$("$TEMPTREE")
assert_eq "755 preserved" "$(stat -f %Lp "$dir/script.sh")" "$(stat -f %Lp "$wt/script.sh")"
assert_eq "444 preserved" "$(stat -f %Lp "$dir/locked.txt")" "$(stat -f %Lp "$wt/locked.txt")"
assert_eq "600 preserved" "$(stat -f %Lp "$dir/secret.txt")" "$(stat -f %Lp "$wt/secret.txt")"
chmod 644 "$dir/locked.txt" "$wt/locked.txt" 2>/dev/null
rm -f "$dir/script.sh" "$dir/locked.txt" "$dir/secret.txt"
remove_wt "$wt"
echo

# === Test 49: rmtree from subdirectory of worktree ===
echo -e "${BOLD}Test 49: rmtree from subdirectory${RESET}"
mkdir -p "$dir/a/b"
echo "deep" > "$dir/a/b/f.txt"
wt=$("$TEMPTREE")
main=$(cd "$wt/a/b" && "$RMTREE")
assert_eq "returns main root" "$dir" "$main"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
rm -rf "$dir/a"
echo

# === Test 50: nested temptree (temptree from inside a temptree) ===
echo -e "${BOLD}Test 50: nested temptree${RESET}"
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

# === Test 51: -n with spaces ===
echo -e "${BOLD}Test 51: -n with spaces${RESET}"
wt=$("$TEMPTREE" -n "my experiment")
assert_eq "creates worktree" "yes" "$(test -d "$wt" && echo yes || echo no)"
assert_contains "name in path" "my experiment" "$wt"
remove_wt "$wt"
echo

# === Test 52: --dry-run with -d ===
echo -e "${BOLD}Test 52: temptree --dry-run with -d${RESET}"
custom_dry_dir=$(mktemp -d)/dry-custom
dry_output=$("$TEMPTREE" --dry-run -d "$custom_dry_dir" 2>&1)
dry_status=$?
assert_eq "exits zero" "0" "$dry_status"
assert_contains "shows custom path" "$custom_dry_dir" "$dry_output"
assert_eq "nothing created" "no" "$(test -e "$custom_dry_dir" && echo yes || echo no)"
echo

# === Test 53: rmtree with relative path ===
echo -e "${BOLD}Test 53: rmtree with relative path${RESET}"
wt=$("$TEMPTREE")
wt_name=$(basename "$wt")
main=$(cd "$TEMPTREE_FOREST_DIR" && "$RMTREE" "./$wt_name")
assert_eq "returns main root" "$dir" "$main"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 54: rmtree with --force and no path (current dir outside forest) ===
echo -e "${BOLD}Test 54: rmtree --force no path${RESET}"
outside_dir=$(mktemp -d)/outside-force-wt
wt=$("$TEMPTREE" -d "$outside_dir")
main=$(cd "$wt" && "$RMTREE" --force)
assert_eq "returns main root" "$dir" "$main"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# === Test 55: rmtree -f no path (current dir outside forest) ===
echo -e "${BOLD}Test 55: rmtree -f no path${RESET}"
outside_dir2=$(mktemp -d)/outside-f-wt
wt=$("$TEMPTREE" -d "$outside_dir2")
main=$(cd "$wt" && "$RMTREE" -f)
assert_eq "returns main root" "$dir" "$main"
assert_eq "worktree removed" "no" "$(test -d "$wt" && echo yes || echo no)"
echo

# --- results ---
echo -e "${BOLD}Results: ${GREEN}$pass passed${RESET}, ${RED}$fail failed${RESET}"
rm -rf "$dir" "$TEMPTREE_FOREST_DIR"
exit "$fail"
