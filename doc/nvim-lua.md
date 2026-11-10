# `.nvim.lua` reference

Full documentation of the workspace-local configuration file. To learn what a
"workspace" is first, see `README.md` in the same directory.

## What it is

Place a `.nvim.lua` in the workspace root and it only applies inside that
workspace. When you switch away (switch tab, change root directory, close tab)
every change registered through `w.*` is rolled back; when you come back it is
loaded again.

Comparisons: Emacs `.dir-locals.el`, VS Code `.vscode/settings.json`, JetBrains
`.idea/`. The difference is that **no new format is needed** here: `w.*` are
just a few registration functions in Lua.

## Location and discovery rules

- Location: `<workspace root>/.nvim.lua`, where the workspace root is the `:tcd` value of the current tab (the name shown on the left of the statusline).
- Only the **root of the current tab** is considered; no recursive search up the parent directories. To configure a subproject in a monorepo, create the file in that subproject directory.
- No file: nothing happens (zero cost, no errors).
- Reload after editing: `:lua require("tab_workspace").reload_local_settings()`, or switch to another root and back. Edit entry point: `<leader>lwe` (creates the file from a template when missing).

## Trust

The first load goes through Neovim's `vim.secure.read`, i.e. the `:trust`
mechanism:

- Untrusted → skipped silently, configuration not applied;
- Choosing to trust writes it into the trust list, after which it loads automatically;
- To revoke trust: `:trust` to inspect/manage.

Because the file is executable Lua, trusting it is a required step; `.nvim.lua`
can do anything, not just the API listed here.

## When it takes effect

| Event | Behaviour |
|---|---|
| `VimEnter` | load for the root of the current tab at startup |
| `TabEnter` | switch tab → unload the old workspace config, load the new one's |
| `DirChanged` | `:tcd` / `:cd` changed the root → same as above |
| `User TabWorkspaceRoot` | `<leader>lws` / `lwr` / `lwR` changed the root → same as above |
| `User TabWorkspaceName` | `<leader>lwN` renamed the workspace → only refreshes the statusline name, no root rescan |
| Session restore `post_load` | sync once after every tab's root has been restored |
| `BufReadPost` / `FileType` | a newly opened file under the root automatically gets `w.opt` and `w.map` applied |

Scope is decided by **whether the file path is under the root**, not by "the
current tab's buffer list", so buffers loaded in the background work too.

## API

All APIs live on the local variable `w` defined at the top of the file
(preset when the file is entered; no require needed).

### `w.opt(table)`

**Buffer-local** options for every buffer under the root. Already open buffers
take effect immediately; later ones automatically.

```lua
w.opt({ tabstop = 4, shiftwidth = 4, expandtab = false, textwidth = 100 })
```

Rollback: each buffer is restored to **its own** original value at load time
(not the global value). Setting the same buffer twice records only the first
original value.

### `w.global_opt(table)`

Global options (`vim.o` level). Suitable for `spelllang`, `path`, `grepprg` and
similar options that have no buffer-local version.

```lua
w.global_opt({ spelllang = { "cjk", "en" } })
w.global_opt({ grepprg = "rg --vimgrep" })
```

Rollback: restore the value from before the change (list-style options are also
restored as-is).

### `w.au(event, opts?, fn)`

Autocommand placed in the workspace's own augroup; **the whole augroup is
deleted when leaving the workspace**, so no cleanup on your side.

```lua
w.au("BufWritePre", { pattern = "*.rs" }, function(args)
  vim.lsp.buf.format({ bufnr = args.buf })
end)

w.au({ "BufEnter", "FocusGained" }, function() end) -- shorthand without opts
```

### `w.cmd(name, fn, opts?)`

User command. Deleted on leave.

```lua
w.cmd("Build", function(args)
  vim.cmd("!make " .. args.args)
end, { nargs = "*", desc = "Build current project" })
```

Command names are global: if a command with the same name already exists (from
another plugin or another workspace) it is skipped with a notice instead of
being overwritten.

### `w.map(modes, lhs, rhs, opts?)`

Buffer-local keymaps for every buffer under the root. Deleted on leave.

```lua
w.map("n", "<leader>B", "<cmd>Build<cr>", { desc = "Build" })
w.map({ "n", "v" }, "<leader>F", function() ... end)
```

Note these are **buffer-local**: they do not occupy global keys and cannot be
triggered accidentally in other projects.

### `w.task(spec)`

Register a task that appears in overseer's `:OverseerRun` (`<leader>ru`) list.
It disappears from the list after leaving the workspace.

| Field | Required | Description |
|---|---|---|
| `name` | ✅ | Name shown in the list |
| `cmd` | ✅ | Command line, either a string (via shell) or a list (spawned directly) |
| `args` | | Argument list appended after `cmd` |
| `cwd` | | Working directory, defaults to `${workspaceFolder}` |
| `env` | | Environment variable table |
| `components` | | overseer components, defaults to `{ "default" }`; add `"on_output_quickfix"` for a quickfix |
| `desc` / `tags` / `condition` | | passed to overseer unchanged |

```lua
w.task({ name = "Build", cmd = { "cargo", "build" }, components = { "default", "on_output_quickfix" } })
w.task({
  name = "Run current test",
  cmd = { "cargo", "test" },
  args = { "${fileBasenameNoExtension}" },
  env = { RUST_BACKTRACE = "1" },
})
```

`${...}` is expanded **at the moment the task starts** (so `${file}` is the
buffer at trigger time).

### `w.launch(spec)`

Register a debug configuration, injected into `dap.configurations[filetype]`,
selectable from `:DapContinue`. Removed by reference on leave.

Apart from `filetype` (which configuration list to inject into), the remaining
fields are a standard nvim-dap configuration, passed through unchanged:

```lua
w.launch({
  name = "Debug current file",
  filetype = "rust",
  type = "codelldb",
  request = "launch",
  program = "${workspaceFolder}/target/debug/app",
  args = {},
  cwd = "${workspaceFolder}",
})
```

Placeholders are **not** expanded here; they are left to nvim-dap at runtime
(it knows `${file}`, `${workspaceFolder}`, `${fileBasename}`, `${fileDirname}`,
`${env:VAR}`, etc.). Because nvim-dap resolves `${workspaceFolder}` to the
current cwd, and the workspace cwd is its root, the two are naturally
consistent.

## Placeholders

Supported in tasks (debug configurations are left to nvim-dap):

| Placeholder | Expands to |
|---|---|
| `${workspaceFolder}` | workspace root |
| `${workspaceFolderBasename}` | last path segment of the root |
| `${file}` | full path of the buffer at trigger time |
| `${fileBasename}` | file name |
| `${fileBasenameNoExtension}` | file name without extension |
| `${fileDirname}` | directory containing the buffer |
| `${fileExtname}` | file extension |

Unknown placeholders are kept verbatim; no guessing.

## Rollback boundaries

| Registration | On leave |
|---|---|
| `w.opt` | each buffer is restored to its own original value |
| `w.global_opt` | original value restored |
| `w.au` | the whole augroup is deleted |
| `w.cmd` | `:delcommand` |
| `w.map` | `nvim_buf_del_keymap` |
| `w.task` | disappears from the overseer template list |
| `w.launch` | removed from `dap.configurations` |

**Not guaranteed to roll back** (deliberately): writing `vim.o` directly, global
`vim.keymap.set`, changing `runtimepath`, installing autocommands in someone
else's augroup, background timers. These are unregistered and cannot be undone
precisely — the file says so at the top. Use `w.*` when you need rollback.

When `vim.secure.read` is untrusted or the file has a syntax error: nothing is
loaded (no half-applied config), and the error goes to `:messages`.

## Example: a Rust project

```lua
-- .nvim.lua
w.opt({ tabstop = 4, shiftwidth = 4, textwidth = 100 })

w.task({ name = "Build", cmd = { "cargo", "build" }, components = { "default", "on_output_quickfix" } })
w.task({ name = "All tests", cmd = { "cargo", "test" }, components = { "default", "on_output_quickfix" } })
w.task({ name = "Clippy", cmd = { "cargo", "clippy", "--all-targets" } })

w.launch({
  name = "Debug executable",
  filetype = "rust",
  type = "codelldb",
  request = "launch",
  program = "${workspaceFolder}/target/debug/app",
})

w.map("n", "<leader>B", "<cmd>OverseerRun<cr>", { desc = "Project tasks" })
```

## Example: configuring only a subproject in a monorepo

`repo/packages/api/.nvim.lua` only applies when that subdirectory becomes the
workspace root. Opening a workspace at `repo/` does not load it at all — there
is no "inherit upwards", which prevents one big repository's config from
silently affecting every subproject.

## Troubleshooting

| Symptom | Check |
|---|---|
| Config has no effect | Does `:messages` show `workspace config: ...`? Is the root really that directory (`:pwd` / statusline)? Has the file been trusted via `:trust`? |
| Options remain after switching away | Did you change options directly with something other than `w.*`? |
| Task does not appear | Check the list in `<leader>ru`; did `w.task` omit `cmd`; is overseer loaded? |
| Debug configuration does not appear | Is `filetype` correct (check `:set ft?` in the current buffer)? Configurations are only listed in `:DapContinue` |

Related tests: `tests/tab_workspace_local_settings.lua` (applies on entering
the project / on new buffers / full restore on leaving / reapplies on return /
tasks and debug injections removed / a syntax error leaves no half-applied
config).
