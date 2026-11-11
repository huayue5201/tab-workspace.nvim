# tab-workspace.nvim — one tab, one workspace

Each tab gets its own buffer set, its own cwd, its own LSP lifecycle and its own
`.nvim.lua`. See [Model](#model) for how that is represented.

## Requirements

- Neovim >= 0.10 (checked by `:checkhealth tab_workspace`).
- No required dependencies: the core (buffer membership, per-tab cwd, LSP lifecycle, multi-root, `.nvim.lua`) is pure Neovim.
- Optional, only for the features listed:

| Optional plugin | Enables |
|---|---|
| [resession.nvim](https://github.com/stevearc/resession.nvim) | saving/restoring workspaces as sessions (`store.lua`, `session.lua`, `session_guard.lua`) |
| [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) | the multi-root tree (external source `workspace`) |
| [overseer.nvim](https://github.com/stevearc/overseer.nvim) | `w.task()` in `.nvim.lua` |
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | `w.launch()` in `.nvim.lua` |
| [bufferline.nvim](https://github.com/akinsho/bufferline.nvim) | not required — the plugin only maintains `buflisted`; redraw is delegated through `on_change` |
| [tab-terminal.nvim](https://github.com/huayue5201/tab-terminal.nvim) | works with no wiring because it uses the tab-scoped cwd; it can also show the workspace name through its optional `workspace_name` host hook |

## Installation

Any plugin manager. With lazy.nvim:

```lua
{
  "huayue5201/tab-workspace.nvim",
  -- optional: enables sessions, multi-root tree, w.task, w.launch
  dependencies = { "stevearc/resession.nvim", "nvim-neo-tree/neo-tree.nvim" },
  opts = { auto_root = true },
}
```

With `vim.pack` or a manual `packpath` entry:

```lua
vim.pack.add({ "https://github.com/huayue5201/tab-workspace.nvim" })
require("tab_workspace").setup({ auto_root = true })
```

Notes:

- `setup()` is **not** called automatically; `plugin/tab_workspace.lua` only defines the `:TabWorkspace` command. Call `setup()` yourself (lazy.nvim does it via `opts`); the plugin works without any configuration.
- No keymaps are registered (see [Keymaps](#keymaps)).
- Nothing is `require`d at startup that needs an optional plugin: neo-tree and resession are loaded on demand.
- Run `:checkhealth tab_workspace` to verify the Neovim version, that the core module loads, and which optional integrations were found.

## Model

One **tab = one workspace**, with no extra "workspace entity / registry":

| Dimension | Carrier |
|---|---|
| Root directory | Tab-scoped `:tcd` (`pinned` explicit lock and `prev` fallback point in `root.lua`) |
| Buffer membership | `tab -> bufnr set` in `state.lua`; `buflisted` reflects only the current tab |
| Language servers | `lsp.lua`: stop a tab's exclusive clients after leaving, start them again on return |
| Persistence | resession sessions (v2 format: `{ root, names, aux }` per tab, in tab order) |
| Local config | `<root>/.nvim.lua`, loaded on entering a workspace, rolled back item by item on leaving (`local_settings.lua`) |
| Auxiliary roots | `roots.lua`: one workspace = 1 main root (cwd) + N auxiliary roots |
| UI anchor | left side of the statusline, `🖿 name n/N +M` (M = number of auxiliary roots), name = last path segment of the root |

By design there is deliberately no global workspace registry: workspaces are
carried by tabs. A workspace name can be aliased per root directory (kept
across tabs and restarts), but the name is only a display label and does not
form an extra entity.

## Multi-root (main root + auxiliary roots)

A workspace can have several roots, but **only the main root is the cwd**
(Neovim's cwd is a single value; `'path'` / `gf` / terminals / `:make` all
follow it, as do `'exrc'` and plugins that depend on the cwd):

| Root | Decided by | Role |
|---|---|---|
| Main root | `:tcd` (`root.lua` auto-detection / manual `lwn`, `lws`) | cwd, gitignore markers, deciding where new buffers belong |
| Auxiliary roots | tab-level list in `roots.lua` | shown side by side in the workspace tree, `roots.find_root()` decides which root a buffer belongs to |

`roots.reconcile()` aligns things when the main root changes: if the new main
root was previously an auxiliary root it is removed from that list; the old
main root is **not** automatically demoted to an auxiliary root (whether to
keep it is the user's decision). Sessions store auxiliary roots in the `aux`
field and restore them on load.

### Tree: `integrations/neo_tree.lua` (neo-tree external source `workspace`)

A dedicated source that shows "main root + auxiliary roots" side by side at the
top level, each line carrying a `main ` / `aux ` badge; expanding one gives the
real directory contents of the filesystem source (same filtering, gitignore,
nesting and watching). It does not reimplement a tree; it reuses neo-tree's own
rendering:

- `renderer.show_nodes` renders the root list once (with `hide_root_node` the synthetic root is skipped and real roots sit at the top level);
- expanding a root → `fs.toggle_directory` → `fs_scan.get_items(state, root_dir, ...)`, where `parent_id` is any real directory;
- `state.path` stays set to the main root (gitignore markers, `refresh` only accepts one).

Commands: `<leader>lwt` or `:Neotree workspace toggle` (the plugin config also
maps `<leader>ew`).
Adding/removing auxiliary roots: `<leader>lw+` (`workspace.attach_root`) /
`<leader>lw-` (`workspace.detach_root`).

What is intentionally not done: turning auxiliary roots into full trees (deep
scan) would noticeably slow down opening a tree in a large repository;
auxiliary roots are collapsed by default and only scanned on expand.

### How other modules treat auxiliary roots

| Module | Behaviour |
|---|---|
| Terminal `tab-terminal.nvim` | cwd of a new terminal = root of the current buffer (may be an auxiliary root); falls back to the main root when there is no file name; in the multi-root tree `<C-t>` opens a terminal in that node's directory; the sidebar group header shows `name +N` |
| `.nvim.lua` | **main root only**: `.nvim.lua` in auxiliary roots is not loaded (one config per workspace) |
| Sessions | auxiliary roots are stored in `tab_workspace.list[i].aux` and restored on load |
| Search / `:grep` | still follows the cwd (main root); for cross-root searches use grug-far with multiple paths |
| statusline | `name n/N +M`, M = number of auxiliary roots |

## File responsibilities

| File | Responsibility |
|---|---|
| `util.lua` | decide which buffers / windows belong to a workspace (special buftypes, sidebars, session loading) |
| `state.lua` | buffer membership table, most recently visited tab |
| `listed.lua` | `buflisted` synchronisation (the only implementation of "listed = visible in the current tab") |
| `lifecycle.lua` | close buffers, clean up orphans of closed tabs |
| `session.lua` | resession extension: export / restore membership |
| `session_guard.lua` | membership validation (prevents "saved as A, opened as B"), autosave policy |
| `store.lua` | the single resession adapter layer: setup / read-write / list / delete / load-side corrections |
| `lsp.lua` | per-tab LSP lifecycle |
| `root.lua` | decide the project root from the current file (marker / LSP), auto-switch the tab root; lock and back |
| `workspace.lua` | switch root, create / close / switch workspaces, save / load sessions, unified picker, attach/detach auxiliary roots |
| `roots.lua` | auxiliary roots: attach/detach/clear/session restore/alignment on main-root change/`find_root` |
| `integrations/neo_tree.lua` | neo-tree external source `workspace`: multi-root tree with main + auxiliary roots side by side |
| `local_settings.lua` | load and roll back `<root>/.nvim.lua`; `w.task` / `w.launch` registration |

The entry point is `lua/tab_workspace/init.lua` (only setup, autocommands and
public API forwarding).

## Lifecycle (who fires when)

```
BufEnter/BufWinEnter  membership in the current tab + maybe_follow (switch root only when the file is outside it)
TabEnter              relist (synchronous, avoids a first-frame flicker) → validate membership + lsp.sync on the next event loop
TabLeave              record the tab in the most-recently-used order (for alternate / tab_items)
TabClosed             root.prune → schedule(lifecycle.prune + lsp.on_tab_closed)
DirChanged / User TabWorkspaceRoot / VimEnter
                      local_settings.sync (load/roll back .nvim.lua)
resession post_load   session.on_post_load → local_settings.sync
```

## Public API

```lua
local ws = require("tab_workspace")

-- Workspaces (one tab = one workspace), ordered by most recent use
ws.picker(opts?)        -- tabs + saved sessions + "open directory" (see below)
ws.tab_items(opts?)     -- { tab, number, name, dir, buffers, current }[]
ws.goto_tab(target)     -- tabpage handle, tab number, or a tab_items() entry
ws.alternate()          -- switch to the most recently used other tab
ws.new_workspace(dir?)  ws.close_workspace()   ws.rename_workspace()
ws.set_workspace_name(name)                    ws.workspace_name(tab?)

-- Roots
ws.root(tab?)           ws.set_root(dir)       ws.prompt_root()
ws.root_back()          ws.root_pinned(tab?)   ws.root_unpin()
ws.attach_root(dir?)    ws.detach_root(dir?)   ws.aux_roots(tab?)   ws.find_root(tab, path)
ws.workspace_tree()

-- Buffers
ws.visible_buffers()    ws.close_buffer(buf)

-- Sessions
ws.save_session(name?)  ws.load_session(name?)  ws.delete_session()  ws.attach_resession()

-- Workspace-local config (.nvim.lua) and cwd recovery
ws.edit_local_settings()  ws.reload_local_settings()  ws.guard_cwd()
```

Predicates that do not depend on a workspace (`is_managed_buf`, `is_float_win`,
`is_ephemeral_win`) live in `require("tab_workspace.util")`; internals such as
`session`, `roots` and `local_settings` are implementation detail.

## Keymaps and commands

The plugin registers **no keymaps**. Map what you need; these are the ones the
API is designed around (put them in your own `boot/keymaps.lua` or `keys.lua`):

```lua
local ws = require("tab_workspace")
vim.keymap.set("n", "<leader>lwn", ws.new_workspace, { desc = "New workspace" })
vim.keymap.set("n", "<leader>lwc", ws.close_workspace, { desc = "Close workspace" })
vim.keymap.set("n", "<leader>lwa", ws.alternate, { desc = "Alternate workspace" })
vim.keymap.set("n", "<leader>lwl", ws.picker, { desc = "Workspace/session list" })
vim.keymap.set("n", "<leader>lwN", ws.rename_workspace, { desc = "Rename workspace" })
vim.keymap.set("n", "<leader>lst", ws.save_session, { desc = "Save session" })
vim.keymap.set("n", "<leader>lsd", ws.delete_session, { desc = "Delete session" })
vim.keymap.set("n", "<leader>lws", ws.prompt_root, { desc = "Pin root" })
vim.keymap.set("n", "<leader>lwr", ws.root_back, { desc = "Previous root (pinned)" })
vim.keymap.set("n", "<leader>lwR", ws.root_unpin, { desc = "Unpin root" })
vim.keymap.set("n", "<leader>lwe", ws.edit_local_settings, { desc = "Edit .nvim.lua" })
vim.keymap.set("n", "<leader>lw+", ws.attach_root, { desc = "Attach root" })
vim.keymap.set("n", "<leader>lw-", ws.detach_root, { desc = "Detach root" })
vim.keymap.set("n", "<leader>lwt", ws.workspace_tree, { desc = "Multi-root tree" })
```

| Key (reference setup) | Action |
|---|---|
| `<leader>lwn` | new workspace (new tab + pick a directory) |
| `<leader>lwc` | close workspace |
| `<leader>lwa` | alternate between the two most recent workspaces |
| `<leader>lwl` | unified workspace/session list (open tabs + saved sessions + new directory; the only entry point for "load session") |
| `<leader>lwN` | rename workspace (alias stored per root directory, persisted; empty + enter = restore default basename) |
| `<leader>lst` / `<leader>lss` / `<leader>lsd` | sessions: save / save tab / delete (with confirmation, skipping the current session) |
| `<leader>lws` / `<leader>lwr` / `<leader>lwR` | pin root / go back to the previous root and pin it / unpin |
| `<leader>lwe` | edit the current workspace's `.nvim.lua` |
| `<leader>lw+` / `<leader>lw-` | attach auxiliary root / detach auxiliary root (the main root stays the cwd) |
| `<leader>lwt` / `<leader>ew` | multi-root tree (neo-tree `workspace` source, panel name Workspace) |

Every action is also available through the `:TabWorkspace` command defined by
`plugin/tab_workspace.lua` if you prefer not to map anything:

```vim
:TabWorkspace                  " picker (same as :TabWorkspace picker)
:TabWorkspace new [dir]        " new workspace
:TabWorkspace close            " close current workspace
:TabWorkspace rename           " rename current workspace
:TabWorkspace edit             " edit the current workspace's .nvim.lua
:TabWorkspace reload           " reload .nvim.lua now
:TabWorkspace attach [dir]     " attach auxiliary root
:TabWorkspace detach [dir]     " detach auxiliary root
:TabWorkspace tree             " multi-root tree (needs neo-tree)
```

### Many tabs: switch by list, not by number

Tab numbers shift whenever a tab is closed, so the plugin tracks its own
most-recently-used order and exposes it as data:

- `ws.tab_items()` — every workspace with `name`, `dir`, `buffers` and
  `current`, current tab first, then most recently used, then never-visited
  tabs in tab order. `{ order = "number" }` sorts by tab number instead.
- `ws.goto_tab(target)` — jump to a handle, a tab number, or an item from the
  list above.
- `ws.picker()` — the built-in UI on top of the same list (plus saved sessions
  and "open directory"), so a long tab history is one keystroke away.

`ws.picker()` calls `vim.ui.select`; pass `select` to plug in your own UI (same
signature: `select(items, { prompt, format_item }, on_choice)`):

```lua
local picker = require("my.picker")
ws.picker({ select = picker.select })
```

## `.nvim.lua` (workspace-local config)

Placed in the workspace root, it behaves like Emacs `.dir-locals.el` or VS Code
`.vscode/settings.json`: configuration follows the directory and is restored
item by item when leaving the workspace. The full reference (all `w.*` options,
placeholders, rollback matrix, examples, troubleshooting) is in
[doc/nvim-lua.md](./doc/nvim-lua.md); the following is only a quick overview.

```lua
w.opt({ tabstop = 4, shiftwidth = 4 })          -- buffer-local options for every buffer under the root
w.global_opt({ spelllang = { "cjk", "en" } })   -- global options
w.au("BufWritePre", { pattern = "*.rs" }, function(args) end)
w.cmd("Build", function(args) end, { desc = "Build" })
w.map("n", "<leader>B", "<cmd>Build<cr>", { desc = "Build" })
w.task({ name = "Build", cmd = { "make" }, cwd = "${workspaceFolder}" })
w.launch({ name = "Debug", filetype = "rust", type = "codelldb", request = "launch" })
```

- **Trust**: goes through Neovim's `:trust` (`vim.secure.read`). While untrusted the file is skipped silently; re-enter the workspace after `:trust`.
- **Scope**: decided by "is the file path under the root" (not by the current tab), so buffers loaded in the background work too; newly opened files are picked up through `BufReadPost` / `FileType`.
- **Rollback**: restore per-buffer original options → restore global options → delete user commands → delete buffer-local keymaps → delete the whole augroup → remove injected debug configurations from `dap.configurations` by reference.
- **Limits**: only changes registered through `w.*` are guaranteed to roll back; any other Lua side effects in the file (changing `runtimepath`, installing global keymaps, ...) are unprotected — deliberately, to avoid pretending that everything can be undone.
- `w.task` integrates with overseer (`:OverseerRun` / `<leader>ru`), `w.launch` with nvim-dap (`:DapContinue`).
  `${workspaceFolder}` / `${file}` / `${fileBasename}` / `${fileDirname}` in tasks are expanded when the task starts;
  placeholders in debug configurations are left as-is and expanded by nvim-dap at runtime (it knows the same variables).
- Why not `'exrc'`: it only scans the startup directory once at startup, entering another project via `:tcd` neither loads nor rolls back, and it executes unregistered bare Lua. With `takeover_exrc = true` this module turns `exrc` off so that `.nvim.lua` is exclusively its own.

## Tests

```sh
tests/run.sh
# or individually:
nvim --headless -u NONE -l tests/tab_workspace_root.lua
nvim --headless -u NONE -l tests/tab_workspace_session.lua
nvim --headless -u NONE -l tests/tab_workspace_local_settings.lua
nvim --headless -u NONE -l tests/tab_workspace_roots.lua
nvim --headless -u NONE -l tests/tab_workspace_multiroots_ux.lua   # multi-root user flows (tree/session/tab)
nvim --headless -u NONE -l tests/tab_workspace_name.lua            # workspace aliases
nvim --headless -u NONE -l tests/smoke.lua                         # setup works without optional deps
```

All of them are "user-perspective" behaviour tests: they only perform actions a
user would (":edit", ":tcd", open tabs, call the API) and assert observable
results such as `getcwd()`, `buflisted`, option values, and whether a
command/template exists — never internal implementation details.


## Configuration

```lua
require("tab_workspace").setup({
  auto_root = true,
  root_markers = nil,          -- nil = use the built-in generic marker list
  takeover_exrc = false,       -- true = turn off 'exrc', .nvim.lua takes over
  is_server_enabled = nil,     -- fun(name, bufnr): boolean?
  hide_in_bar = nil,           -- fun(bufnr): boolean? (defaults to buftype)
  on_change = nil,             -- fun(): redraw after buflisted changes
  excluded_filetypes = nil,    -- table<string, boolean>: sidebar fts excluded from membership

  -- LSP lifecycle per tab
  lsp_stop_on_leave = true,    -- stop clients the tab no longer uses after leaving
  lsp_restart_on_enter = true, -- restart them when coming back
  lsp_stop_delay = 5000,       -- ms to wait before stopping (covers fast tab switching)

  guard_cwd = true,            -- recover from a deleted cwd (see below)
})
```

### Deleted cwd recovery

Neovim keeps per-tab cwds and `chdir`s when you switch tabs, but nothing checks
that those directories still exist. Two very different symptoms follow:

- **Invalid process cwd** — nvim was started from a directory that no longer
exists (a close Terminal window, a removed worktree, a cleaned `/tmp`).
`vim.uv.cwd()` returns `nil` and `vim.fn.getcwd()` returns `""`, so every
plugin that touches cwd during `setup()` fails at its first assert: lazydev and
obsidian `assert(uv.cwd())`, neogit `cwd:gsub(...)`, procman `fs_scandir(nil)`,
codecompanion `vim.fs.abspath`, and fff misreads the empty path as “scan `/`”.
- **Stale tab cwd** — a tab's `:tcd` target was deleted afterwards. Switching to
it makes `chdir` fail silently: the process stays in the previous tab's
directory, so new files, terminals and LSP roots all land in the wrong project.

`guard_cwd` (on by default) repairs both: `setup()` fixes an invalid process cwd
before anything else, and `TabEnter` re-checks each tab's `:tcd` value, falling
back to (in order) the tab's last valid cwd, the directory of a file shown in
that tab, `$HOME`, `$XDG_CONFIG_HOME`, then the nvim executable's directory —
with a single warning so you know it happened. Because the failures above occur
inside other plugins' `setup()`, call the guard early if you load plugins before
`tab_workspace`:

```lua
require("tab_workspace.cwd_guard").ensure()  -- idempotent; no autocmds registered
```

The plugin registers **no keymaps by default** and does not require any UI,
sidebar or session plugin. The host wires in what it needs:

```lua
-- bufferline: the plugin only changes buflisted, redrawing is up to the host
on_change = function()
  local bl = package.loaded["bufferline"]
  if type(bl) == "table" and type(bl.redraw) == "function" then return bl.redraw() end
  vim.schedule(function() pcall(vim.cmd, "redrawtabline") end)
end

-- per-project start/stop such as lsp_ext.servers
is_server_enabled = function(name, bufnr) ... end
```

### neo-tree multi-root tree (optional)

Add `tab_workspace.integrations.neo_tree` to neo-tree's `sources` (its source
name is `workspace`), then wire the tab operations to this plugin:

```lua
require("neo-tree").setup({ sources = { "filesystem", "tab_workspace.integrations.neo_tree" } })
vim.keymap.set("n", "<leader>lwt", "<cmd>Neotree workspace toggle<cr>")
```

That file is loaded on demand, the core modules never require neo-tree, and
everything else keeps working when neo-tree is not installed.

### resession (optional)

```lua
require("tab_workspace.store").setup()          -- the single resession adapter layer
require("tab_workspace").attach_resession()     -- post_load hook
require("tab_workspace.session_guard").setup_autosave({ interval = 60 })
```

The session extension name is `tab_workspace`
(`resession.extensions.tab_workspace`).
