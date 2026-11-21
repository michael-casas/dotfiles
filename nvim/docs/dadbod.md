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
- The file sits outside every checkout. Envi's config, `~/.config/nvim`, is a link into the dotfiles checkout (and a dev profile's into its worktree), so a file there could be committed.

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

`:DBUIAddConnection` asks for a URL, then a name. Dadbod UI saves the connection in `connections.json` under `g:db_ui_save_location`, which is `~/.local/share/nvim/dadbod_ui`. That's envi's data directory, outside git, and `envi-dev` profiles share it. Saved queries go in the same place. To remove a connection, press `d` on it in the drawer.

The file is plain text, so envi refuses a URL that carries a password (see [Where secrets live](#where-secrets-live)).

### 3. The environment (`DBUI_URL`)

Set `DBUI_URL` and, optionally, `DBUI_NAME` in the shell that starts envi:

```bash
DBUI_URL='postgres://me@localhost/app_dev' DBUI_NAME=app-dev envi
```

Without `DBUI_NAME`, the drawer uses the last path segment of the URL as the name.

### Postgres service file

`postgres:///?service=<name>` connects through an entry in `~/.pg_service.conf`, or in `$PGSERVICEFILE` if that's set. `psql` reads the file, so any of the three sources can use a service URL. The repo's `postgres/.pg_service.conf` is a reference copy.

## Where secrets live

Postgres passwords live in one place, never in git: a passfile, mode 600.

- **`~/.pgpass`**, or the file `PGPASSFILE` names. Each line is `host:port:database:user:password`, and `*` matches any value in the first four fields. Create it with `chmod 600`, or `psql` ignores it. Dadbod always runs `psql -w`, which never prompts and reads the passfile.
- **Optionally, a service entry** in `~/.pg_service.conf` (or `$PGSERVICEFILE`): host, port, database and user, **with no password**. Connect with `postgres:///?service=<name>`, and the passfile supplies the password.

Envi enforces this for both `postgres:` and `postgresql:` URLs:

- **A URL that carries a password is refused,** whether it's `user:password@host` or a `password=` parameter or conninfo keyword. That covers `:DB`, a query run, a connection from `dbs.lua` or `DBUI_URL`, `:DBUIAddConnection` and renaming a connection. `:DBUIAddConnection` and rename refuse it before anything is saved to `connections.json`. The error never repeats the URL.
- **Dadbod never prompts for a password** to retry a failed connection. Fix the passfile instead.
- **An inherited `PGPASSWORD` is ignored by Dadbod's `psql`,** so a stale value can't override the passfile. Terminals and other jobs started from envi keep it.

A password never belongs in a connection URL: Dadbod passes URLs on the `psql` command line, and `connections.json` stores them in plain text.

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

The `-X`, and the password rules above, come from `autoload/envi/dadbod_postgresql.vim`. vim-dadbod's `g:db_adapter_postgresql` and `g:db_adapter_postgres` point both Postgres schemes at it. It builds the same `psql` command lines as vim-dadbod's own Postgres adapter, with `-X` as the only startup-file flag.
