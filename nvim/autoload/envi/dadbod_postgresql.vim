" vim-dadbod's postgresql adapter for envi. lua/plugins/dadbod.lua points
" g:db_adapter_postgresql and g:db_adapter_postgres here. Compared with
" upstream (db#adapter#postgresql#):
"
" - psql runs with -X, so ~/.psqlrc (timing, borders, null display) stays out
"   of Dadbod's results and out of the output Dadbod UI parses. Plain psql
"   elsewhere still reads it.
" - libpq decides what is a password. envi.libpq (lua/envi/libpq.lua) runs
"   libpq's own parser, PQconninfoParse, on the connection operand psql will
"   receive. A string is refused exactly where libpq would read a password
"   from it, and wherever libpq rejects what would run; nothing else is
"   classified (file paths, SQL, other option values). The checks run in
"   canonicalize, which :DBUIAddConnection and rename call before saving, and
"   on the --dbname operand of every psql command built here. The errors are
"   fixed texts: never the URL, never libpq's own message (it can quote the
"   password). Passwords live in ~/.pgpass or $PGPASSFILE.
" - Without libpq, Postgres URLs are refused: nothing can say whether they
"   carry a password.
" - Key/value conninfo after the scheme (postgresql:host=... dbname=...) is
"   refused with a pointer to the URL form. vim-dadbod's canonicalize turns
"   it into an encoded database name, so it never connected.
" - Where upstream's canonicalize would change libpq's reading of a URI
"   (e.g. an encoded `;` in a value), the URI is kept as written.
" - vim-dadbod's password prompt-and-retry is off (auth_pattern).
" - An inherited PGPASSWORD is left out of Dadbod's psql processes only, so
"   the passfile is what authenticates them. Other jobs keep it.

function! s:verdict(operand) abort
  return luaeval('require("envi.libpq").classify(_A)', a:operand)
endfunction

function! s:meaning(operand) abort
  return luaeval('require("envi.libpq").meaning(_A)', a:operand)
endfunction

function! s:is_uri(url) abort
  " libpq's URI designators are case-sensitive.
  return a:url =~# '^postgres\%(ql\)\=://'
endfunction

" The --dbname operand upstream's interactive builder passes for a URL.
function! s:operand(url) abort
  return get(db#adapter#postgresql#interactive(a:url), -1, '')
endfunction

function! s:refuse(verdict) abort
  if a:verdict ==# 'password'
    throw 'DB: envi refuses a Postgres URL that carries a password. '
          \ . 'Put the password in ~/.pgpass or $PGPASSFILE (see nvim/docs/dadbod.md).'
  elseif a:verdict ==# 'invalid'
    throw "DB: libpq can't parse this Postgres URL, so envi won't save or run it."
  elseif a:verdict ==# 'nolib'
    throw "DB: envi couldn't load libpq to check this Postgres URL, so it won't save or run it. "
          \ . 'Install libpq (it ships with psql) or set $ENVI_LIBPQ (see nvim/docs/dadbod.md).'
  elseif a:verdict ==# 'keyword/value'
    throw "DB: Dadbod can't use keyword/value conninfo after postgresql:. "
          \ . 'Use a postgresql:// URI, or postgresql:///?service=<name> (see nvim/docs/dadbod.md).'
  endif
endfunction

" postgres[ql]: followed by anything but //, holding `=` or whitespace.
function! s:is_keyword_value(url) abort
  let rest = matchstr(a:url, '\c^postgres\%(ql\)\=:\zs.*')
  return a:url =~? '^postgres\%(ql\)\=:' && rest !~# '^//' && rest =~# '[=[:space:]]'
endfunction

" A URL as stored or about to run: refuse it if libpq reads a password from
" the URL itself (a URI) or from its operand, or if libpq can't be loaded.
" When it is what will run (a:final), refuse an operand libpq rejects too.
function! s:check(url, final) abort
  if s:is_keyword_value(a:url)
    call s:refuse('keyword/value')
  endif
  for operand in s:is_uri(a:url) ? [a:url, s:operand(a:url)] : [s:operand(a:url)]
    let verdict = s:verdict(operand)
    if verdict ==# 'password' || verdict ==# 'nolib' || (a:final && verdict ==# 'invalid')
      call s:refuse(verdict)
    endif
  endfor
endfunction

" psql -X: one startup-file flag. Upstream's command lines start with psql.
function! s:no_psqlrc(cmd) abort
  if get(a:cmd, 0, '') !=# 'psql'
        \ || index(a:cmd, '-X') >= 0 || index(a:cmd, '--no-psqlrc') >= 0
    return a:cmd
  endif
  return [a:cmd[0], '-X'] + a:cmd[1:]
endfunction

" Check the connection operand (--dbname's value, or a:1 for a positional
" one), then leave an inherited PGPASSWORD out of the psql process. The env
" binary is given by path: vim-dadbod treats a literal `env` first word as
" VAR=value settings for the job, which cannot unset anything.
function! s:command(cmd, ...) abort
  let i = index(a:cmd, '--dbname')
  let operand = a:0 ? a:1 : (i >= 0 ? get(a:cmd, i + 1, '') : '')
  let verdict = s:verdict(operand)
  if verdict !=# 'clean' && verdict !=# 'literal'
    call s:refuse(verdict)
  endif
  if !exists('$PGPASSWORD')
    return a:cmd
  endif
  let env = exepath('env')
  return [empty(env) ? '/usr/bin/env' : env, '-u', 'PGPASSWORD'] + a:cmd
endfunction

function! s:parse_columns(output, column) abort
  let rows = map(copy(a:output), 'split(v:val, "|")')
  return map(filter(rows, 'len(v:val) > a:column'), 'v:val[a:column]')
endfunction

function! envi#dadbod_postgresql#canonicalize(url) abort
  call s:check(a:url, 0)
  let url = db#adapter#postgresql#canonicalize(a:url)
  call s:check(url, 0)
  " Keep a URI as written when upstream's rewrite would change libpq's
  " reading of it.
  if url !=# a:url && s:is_uri(a:url)
        \ && s:meaning(s:operand(url)) !=# s:meaning(s:operand(a:url))
    let url = a:url
  endif
  call s:check(url, 1)
  return url
endfunction

function! envi#dadbod_postgresql#interactive(url, ...) abort
  return s:command(s:no_psqlrc(call('db#adapter#postgresql#interactive', [a:url] + a:000)))
endfunction

function! envi#dadbod_postgresql#filter(url) abort
  return s:command(s:no_psqlrc(db#adapter#postgresql#filter(a:url)))
endfunction

function! envi#dadbod_postgresql#input(url, in) abort
  return s:command(s:no_psqlrc(db#adapter#postgresql#input(a:url, a:in)))
endfunction

" Upstream's \dtvm listing, with -X instead of an added --no-psqlrc.
function! envi#dadbod_postgresql#tables(url) abort
  let cmd = s:no_psqlrc(db#adapter#postgresql#filter(a:url)) + ['-tA', '-c', '\dtvm']
  return s:parse_columns(db#systemlist(s:command(cmd)), 1)
endfunction

" Upstream's database list (the URL rewritten to the postgres maintenance
" database, first field of each row), with -X as the only startup-file flag.
" The rewritten target is the operand psql receives, so that is what's checked.
function! envi#dadbod_postgresql#complete_database(url) abort
  let target = substitute(a:url, '/[^/]*$', '/postgres', '')
  return s:parse_columns(db#systemlist(s:command(['psql', '-X', '-wltA', target], target)), 0)
endfunction

function! envi#dadbod_postgresql#complete_opaque(_) abort
  return envi#dadbod_postgresql#complete_database('')
endfunction

" A pattern that matches nothing: vim-dadbod never prompts for a password and
" retries with it in the URL.
function! envi#dadbod_postgresql#auth_pattern() abort
  return '\_.\@!\_.'
endfunction
