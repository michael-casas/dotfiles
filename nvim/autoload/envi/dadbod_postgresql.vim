" vim-dadbod's postgresql adapter for envi. lua/plugins/dadbod.lua points
" g:db_adapter_postgresql and g:db_adapter_postgres here. Compared with
" upstream (db#adapter#postgresql#):
"
" - psql runs with -X, so ~/.psqlrc (timing, borders, null display) stays out
"   of Dadbod's results and out of the output Dadbod UI parses. Plain psql
"   elsewhere still reads it.
" - A URL that carries a password (user:password@ or a libpq `password`
"   parameter) is refused before it is saved or reaches a command line. The
"   check runs in canonicalize, which :DBUIAddConnection and rename call before
"   saving, and again in every function that builds a psql command. The error
"   never includes the URL. Passwords live in ~/.pgpass or $PGPASSFILE.
" - vim-dadbod's password prompt-and-retry is off (auth_pattern).
" - An inherited PGPASSWORD is left out of Dadbod's psql processes only, so
"   the passfile is what authenticates them. Other jobs keep it.

" A libpq password keyword, as a URL parameter or inside a conninfo string.
let s:keyword = '\c\%(^\|[^[:alnum:]_]\)password\s*='

function! s:has_password(url) abort
  if type(a:url) != v:t_string || empty(a:url)
    return 0
  endif
  if a:url =~# s:keyword
    return 1
  endif
  try
    let parsed = db#url#parse(a:url)
  catch
    return a:url =~# '://[^/@:?#]*:[^/@?#]\+@'
  endtry
  if !empty(get(parsed, 'password', ''))
    return 1
  endif
  for key in keys(get(parsed, 'params', {}))
    if key ==? 'password'
      return 1
    endif
  endfor
  " psql receives an opaque part (postgresql:<conninfo>) or, after upstream's
  " canonicalize, the decoded path as --dbname, where conninfo is parsed.
  return get(parsed, 'opaque', '') =~# s:keyword || get(parsed, 'path', '') =~# s:keyword
endfunction

function! s:refuse_password(url) abort
  if s:has_password(a:url)
    throw 'DB: envi refuses a Postgres URL that carries a password. '
          \ . 'Put the password in ~/.pgpass or $PGPASSFILE (see nvim/docs/dadbod.md).'
  endif
endfunction

" psql -X: one startup-file flag. Upstream's command lines start with psql.
function! s:no_psqlrc(cmd) abort
  if get(a:cmd, 0, '') !=# 'psql'
        \ || index(a:cmd, '-X') >= 0 || index(a:cmd, '--no-psqlrc') >= 0
    return a:cmd
  endif
  return [a:cmd[0], '-X'] + a:cmd[1:]
endfunction

" Leave an inherited PGPASSWORD out of the psql process. The env binary is
" given by path: vim-dadbod treats a literal `env` first word as VAR=value
" settings for the job, which cannot unset anything.
function! s:command(cmd) abort
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
  call s:refuse_password(a:url)
  let url = db#adapter#postgresql#canonicalize(a:url)
  call s:refuse_password(url)
  return url
endfunction

function! envi#dadbod_postgresql#interactive(url, ...) abort
  call s:refuse_password(a:url)
  return s:command(s:no_psqlrc(call('db#adapter#postgresql#interactive', [a:url] + a:000)))
endfunction

function! envi#dadbod_postgresql#filter(url) abort
  call s:refuse_password(a:url)
  return s:command(s:no_psqlrc(db#adapter#postgresql#filter(a:url)))
endfunction

function! envi#dadbod_postgresql#input(url, in) abort
  call s:refuse_password(a:url)
  return s:command(s:no_psqlrc(db#adapter#postgresql#input(a:url, a:in)))
endfunction

" Upstream's \dtvm listing, with -X instead of an added --no-psqlrc.
function! envi#dadbod_postgresql#tables(url) abort
  call s:refuse_password(a:url)
  let cmd = s:no_psqlrc(db#adapter#postgresql#filter(a:url)) + ['-tA', '-c', '\dtvm']
  return s:parse_columns(db#systemlist(s:command(cmd)), 1)
endfunction

" Upstream's database list (the URL rewritten to the postgres maintenance
" database, first field of each row), with -X as the only startup-file flag.
function! envi#dadbod_postgresql#complete_database(url) abort
  call s:refuse_password(a:url)
  let cmd = ['psql', '-X', '-wltA', substitute(a:url, '/[^/]*$', '/postgres', '')]
  return s:parse_columns(db#systemlist(s:command(cmd)), 0)
endfunction

function! envi#dadbod_postgresql#complete_opaque(_) abort
  return envi#dadbod_postgresql#complete_database('')
endfunction

" A pattern that matches nothing: vim-dadbod never prompts for a password and
" retries with it in the URL.
function! envi#dadbod_postgresql#auth_pattern() abort
  return '\_.\@!\_.'
endfunction
