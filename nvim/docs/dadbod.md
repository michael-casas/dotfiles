# Dadbod UI in envi

[Dadbod UI](https://github.com/kristijanhusak/vim-dadbod-ui) gives envi a database drawer, SQL query buffers and result buffers. It runs on [vim-dadbod](https://github.com/tpope/vim-dadbod), and [vim-dadbod-completion](https://github.com/kristijanhusak/vim-dadbod-completion) adds table and column completion. The spec is `lua/plugins/dadbod.lua` and the revisions are pinned in `lazy-lock.json`.

The plugins load on first use of `:DBUI`, `:DBUIToggle`, `:DBUIAddConnection`, `:DBUIFindBuffer` or `:DB`, or when a SQL buffer opens. Envi adds no global key for them.

Each database needs its command-line client on `PATH`: `psql` for Postgres, `sqlite3` for SQLite, and so on.

## Open the drawer

`:DBUIToggle` opens or closes the drawer. Press `?` in it for its keys:

- `o` or `<CR>` expands a connection or a table, or opens an item;
- `R` redraws the drawer;
- `d` deletes a saved connection or query;
- `r` renames one;
- `A` adds a connection, like `:DBUIAddConnection`;
- `q` closes the drawer.

## Add connections

The drawer lists every connection from all three sources at once. It labels each one with its scheme and source, for example `shop (sqlite - g:dbs)`.

### 1. A local file (`g:dbs`)

Write `~/.config/envi-local/dbs.lua`. Envi reads it when Dadbod UI loads and sets `g:dbs` from it.

- If `XDG_CONFIG_HOME` is set, the file is `$XDG_CONFIG_HOME/envi-local/dbs.lua`.
- `ENVI_DBS_FILE=<path>` points at a different file.
- The file sits outside every checkout. `~/.config/envi` is a link into a dotfiles worktree, so a file there could be committed.

```lua
-- ~/.config/envi-local/dbs.lua: never put passwords here.
return {
  { name = "app-dev", url = "postgres://me@localhost:5432/app_dev" },
  { name = "warehouse", url = "postgres:///?service=warehouse" },
  { name = "scratch", url = "sqlite:" .. vim.fn.expand("~/scratch.db") },
}
```

A `{ name = url }` table works too. Restart envi after you edit the file, or run `:reload`.

### 2. `:DBUIAddConnection`

`:DBUIAddConnection` asks for a URL, then a name. Dadbod UI saves the connection in `connections.json` under `g:db_ui_save_location`, which is `~/.local/share/envi/dadbod_ui`. That's envi's data directory, outside git. Saved queries go in the same place. To remove a connection, press `d` on it in the drawer.

The file is plain text, so the URL you type should carry no password.

### 3. The environment (`DBUI_URL`)

Set `DBUI_URL` and, optionally, `DBUI_NAME` in the shell that starts envi:

```bash
DBUI_URL='postgres://me@localhost/app_dev' DBUI_NAME=app-dev envi
```

Without `DBUI_NAME`, the drawer uses the last path segment of the URL as the name.

### Postgres service file

`postgres:///?service=<name>` connects through an entry in `~/.pg_service.conf`, or in `$PGSERVICEFILE` if that's set. `psql` reads the file, so any of the three sources can use a service URL. The repo's `postgres/.pg_service.conf` is a reference copy.

## Where secrets live

Never in git, and never in a connection URL. Dadbod passes URLs on the `psql` command line, and `connections.json` stores them in plain text. Use one of these instead:

- **`~/.pgpass`** (mode 600): `host:port:db:user:password`. `psql -w` reads it, and Dadbod always passes `-w`. `PGPASSFILE` points at another file.
- **The service file:** host, port, database and user, with no password. Pair it with `.pgpass`.
- **The macOS keychain:** to have `dbs.lua` fetch a password when it loads, call `vim.fn.system({ "security", "find-generic-password", "-s", "<item>", "-w" })` and build the URL from the result. The password then sits in memory and on the `psql` command line, so prefer `.pgpass` where you can.

## Switch connections

- In the drawer, expand a connection and open **New query**. The query buffer is bound to that connection, and its name starts with the connection's name (`shop-query-…`). Open a new query under another connection to work on both side by side.
- Write the buffer (`:w`) to run it. The results open in a `dbout` split under it. To run part of a query, select it in Visual mode and use `:'<,'>DB`. The query buffer's own key, `<leader>S`, also works.
- `:DBUIFindBuffer` binds the current `.sql` file to a connection you pick.
- `:DB <url> <query>` runs a one-off query without the drawer. In a bound buffer, `:%DB` runs the whole buffer.

## Completion

In a query buffer, blink.cmp offers tables, columns and SQL keywords from the `dadbod` source. That source is enabled for `sql`, `mysql` and `plsql` only. `<C-x><C-o>` gives the same list through the omnifunc.

## Colours

The drawer, query buffers and result buffers use the active colorscheme's highlight groups, and they repaint on `:colorscheme`. The drawer's connection markers (✓ and ✕) default to fixed colours. `after/syntax/dbui.lua` links them to `DiagnosticOk` and `DiagnosticError` instead.

## `~/.psqlrc`

Dadbod runs `psql -X`, so `~/.psqlrc` stays out of its results: no "Timing is on." or other preamble lines, and `psql`'s default borders and null display. The drawer's table and foreign-key helpers parse that default output too. A plain `psql` in a shell still reads `~/.psqlrc`.

The `-X` comes from `autoload/envi/dadbod_postgresql.vim`. vim-dadbod's `g:db_adapter_postgresql` and `g:db_adapter_postgres` point both Postgres schemes at it. Its functions call vim-dadbod's own Postgres adapter, and the ones that build a `psql` command line add `-X`.
