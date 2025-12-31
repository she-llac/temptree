# temptree

Fast, disposable Git worktrees for AI agents and throwaway experiments.

```sh
temptree              # create a disposable worktree with your uncommitted changes
# ... let an agent loose, experiment freely ...
rmtree                # clean up and return to main repo
```

Creates a detached worktree and copy-on-write copies your working tree into it —
uncommitted changes included. Your main checkout stays untouched.

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

Both scripts support `-h`/`--help` for quick reference.

## Install

1. Put the scripts on your PATH:

```sh
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

### With vs. without shell helpers

| Action | Without helpers | With helpers |
|--------|-----------------|--------------|
| `temptree` | Prints new worktree path | Prints path and `cd`s into it |
| `rmtree` (no args) | Prints main repo path | Prints path and `cd`s back |
| `rmtree <path>` | Prints main repo path | Prints path (no `cd`) |

## Environment variables

| Name | Default | Description |
|------|---------|-------------|
| `TEMPTREE_FOREST_DIR` | `$HOME/forest` | Base directory for temp worktrees (absolute path) |
| `TEMPTREE_PRUNE_FOREST` | `1` | Set to `0` to keep the forest dir when it becomes empty |

## How it works

1. `temptree` creates a detached Git worktree at the specified ref
2. It then CoW-copies your entire working tree (including uncommitted changes and dotfiles) into the worktree
3. The worktree is named `<repo>-<random>` under the forest dir (e.g., `~/forest/myproject-0042`)
4. `rmtree` removes the worktree via `git worktree remove` and cleans up

Copy-on-write is auto-detected:
- macOS/APFS: `cp -c`
- Linux with reflink support: `cp --reflink=auto`
- Fallback: regular `cp -a`

If creation fails partway through, the incomplete worktree is automatically cleaned up.

## Notes

- `temptree` only works inside a Git repository
- `rmtree` refuses to delete worktrees outside the forest dir unless you pass `-f`/`--force`
- Dotfiles (e.g., `.env`) are copied along with everything else
- The `.git` directory is not copied (it's managed by Git's worktree mechanism)

## License

MIT
