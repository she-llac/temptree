# temptree

Fast, disposable Git worktrees for AI agents and throwaway experiments.

```sh
temptree              # create a disposable worktree with your uncommitted changes
# ... let an agent loose, experiment freely ...
rmtree                # clean up and return to main repo
```

Creates a detached worktree and copies your working tree into it (using
copy-on-write when available), uncommitted changes included. Your main checkout
stays untouched.

## Usage

Create a temp worktree at `HEAD` (includes uncommitted changes):

```sh
temptree
# => ~/forest/myrepo-2137
```

Create at a specific ref:

```sh
temptree my-branch
```

> **Note:** The ref controls what git history is visible in the worktree, not
> the file contents. Files are always copied from your current working tree.
> This means `temptree my-branch` gives you your uncommitted work with
> `git log` showing `my-branch`.

Create at a specific ref in a specific directory:

```sh
temptree my-branch /tmp/my-wt
```

Specify only a directory (ref defaults to `HEAD`):

```sh
temptree -d /tmp/my-wt
```

Remove a worktree by path:

```sh
rmtree ~/forest/myrepo-2137
```

Remove the current worktree (when inside one):

```sh
rmtree
```

Remove a worktree outside the forest dir (requires `--force`):

```sh
rmtree -f /tmp/my-wt
```

### Dry run

Preview what either command would do without making changes:

```sh
temptree --dry-run
temptree --dry-run -n experiment HEAD~1
rmtree --dry-run ~/forest/myrepo-2137
```

Both scripts support `-h`/`--help` for quick reference.

## Install

1. Put the scripts on your PATH:

```sh
# symlink (updates when you git pull)
ln -s "$(pwd)/temptree" "$(pwd)/rmtree" /usr/local/bin/

# or copy
cp temptree rmtree /usr/local/bin/
```

2. (Optional) Add shell helpers for auto-cd behavior:

**Bash/Zsh:**

```sh
cat shell_helpers.sh >> ~/.bashrc   # or ~/.zshrc
```

**Fish:**

```sh
cat fish_helpers.fish >> ~/.config/fish/config.fish
```

**Nushell:**

```nu
open nushell_helpers.nu | save --append $nu.config-path
```

### With vs. without shell helpers

| Action | Without helpers | With helpers |
|--------|-----------------|--------------|
| `temptree` | Prints new worktree path | `cd`s into it (no output) |
| `rmtree` (no path) | Prints main repo path | `cd`s back (no output) |
| `rmtree <path>` | Prints main repo path | No `cd` (no output) |

> `rmtree -f` (flags but no path) is treated the same as no-args — the helpers
> `cd` back when no path operand is given.

## Environment variables

| Name | Default | Description |
|------|---------|-------------|
| `TEMPTREE_FOREST_DIR` | `$HOME/forest` | Base directory for temp worktrees (absolute path) |
| `TEMPTREE_PRUNE_FOREST` | `1` | Set to `0` to keep the forest dir when it becomes empty |

## How it works

1. `temptree` creates a detached Git worktree at the specified ref
2. It then copies your entire working tree (including uncommitted changes and dotfiles) into the worktree, using CoW when available
3. If no directory was specified, the worktree is named `<repo>-<random>` under the forest dir (e.g., `~/forest/myproject-0042`)
4. `rmtree` removes the worktree via `git worktree remove` and cleans up

Copy-on-write is auto-detected:
- macOS/APFS: `cp -c`
- Linux with reflink support: `cp --reflink=auto`
- Fallback: regular `cp -a`

If creation fails partway through, the incomplete worktree is automatically cleaned up.

## Notes

- `temptree` only works inside a Git repository
- `rmtree` refuses to delete worktrees outside the forest dir unless you pass `-f`/`--force`
- `rmtree` refuses to delete the main worktree of a repository (even with `--force`)
- Everything is copied: untracked files, ignored files, dotfiles, all of it
- The `.git` directory is the only exception (it's managed by Git's worktree mechanism)

## Testing

62 tests (161 assertions) covering both scripts end-to-end:

```sh
bash test.sh
```

## See also

- [git-snapshot](https://github.com/she-llac/git-snapshot) - zero-side-effect working tree snapshots for Git
- [try](https://github.com/tobi/try) - fuzzy-searchable experiment directories with auto-dating

## License

MIT
