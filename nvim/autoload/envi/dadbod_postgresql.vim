" vim-dadbod's postgresql adapter for envi. lua/plugins/dadbod.lua points
" g:db_adapter_postgresql and g:db_adapter_postgres here. Compared with
" upstream (db#adapter#postgresql#):
"
" - psql runs with -X, so ~/.psqlrc (timing, borders, null display) stays out
"   of Dadbod's results and out of the output Dadbod UI parses. Plain psql
"   elsewhere still reads it.
" - A connection string that carries a password is refused before it is saved
"   or reaches a command line, in every form libpq accepts: URI userinfo
"   (single or multi-host, IPv6, empty user or host), a `password` URI
"   parameter or key/value conninfo keyword in any case or percent-encoding,
"   and conninfo reached through vim-dadbod's rewrites. One classifier,
"   s:carries_password(), serves both checks: canonicalize (which
"   :DBUIAddConnection and rename call before saving) and every psql command
"   this adapter builds. The error never includes the URL. Passwords live in
"   ~/.pgpass or $PGPASSFILE.
" - vim-dadbod's password prompt-and-retry is off (auth_pattern).
" - An inherited PGPASSWORD is left out of Dadbod's psql processes only, so
"   the passfile is what authenticates them. Other jobs keep it.

" Percent-decoding, repeated until nothing changes so a doubly encoded key
" can't hide either. libpq decodes URI keys and values once.
function! s:decode(str) abort
  let str = a:str
  for _ in range(5)
    let next = substitute(str, '%\(\x\x\)', '\=nr2char(str2nr(submatch(1), 16))', 'g')
    if next ==# str
      break
    endif
    let str = next
  endfor
  return str
endfunction

function! s:is_password_key(key) abort
  return trim(s:decode(a:key)) ==? 'password'
endfunction

" Key/value conninfo (`host=x password='y z'`), tokenized as libpq does:
" keyword, optional spaces, `=`, optional spaces, then a single-quoted value
" (backslash escapes) or a run of non-space characters. Any password keyword
" counts, whatever its value: libpq reads `password= host=x` as the password
" "host=x". A dbname value may itself be a URI or conninfo.
function! s:conninfo_has_password(str) abort
  let rest = a:str
  while rest =~# '\S'
    let m = matchlist(rest, '^\s*\([^=[:space:]]\+\)\s*=\s*')
    if empty(m)
      return 0
    endif
    let rest = strpart(rest, len(m[0]))
    let value = rest[0] ==# "'"
          \ ? matchstr(rest, '^''\%(\\.\|[^''\\]\)*''\=')
          \ : matchstr(rest, '^\%(\\.\|\S\)*')
    let rest = strpart(rest, len(value))
    if s:is_password_key(m[1])
      return 1
    endif
    if trim(s:decode(m[1])) ==? 'dbname'
          \ && s:carries_password(substitute(value, '^''\(.*\)''$', '\1', ''))
      return 1
    endif
  endwhile
  return 0
endfunction

" URI query parameters: `&`-separated (vim-dadbod also splits on `;`), keys
" percent-decoded before the case-insensitive comparison.
function! s:query_has_password(query) abort
  for item in split(a:query, '[&;]')
    let key = matchstr(item, '^[^=]*')
    if s:is_password_key(key)
      return 1
    endif
    if trim(s:decode(key)) ==? 'dbname' && s:carries_password(s:decode(matchstr(item, '=\zs.*')))
      return 1
    endif
  endfor
  return 0
endfunction

" A libpq URI: postgres[ql]://[user[:password]@][host[:port][,...]][/dbname][?params].
function! s:uri_has_password(uri) abort
  let rest = matchstr(a:uri, '\c^postgres\%(ql\)\=://\zs.*')
  let query = ''
  let qmark = stridx(rest, '?')
  if qmark >= 0
    let query = strpart(rest, qmark + 1)
    let rest = strpart(rest, 0, qmark)
  endif
  " libpq: the credentials end at the first `@` before any `/`, whatever the
  " host list after it holds (commas, IPv6 brackets, nothing).
  let authority = matchstr(rest, '^[^/]*')
  let at = stridx(authority, '@')
  if at >= 0
    if !empty(s:decode(matchstr(strpart(authority, 0, at), ':\zs.*')))
      return 1
    endif
  elseif stridx(rest, '@') >= 0 && strpart(rest, 0, stridx(rest, '@')) =~# ':'
    " An unencoded `/` in a password ends libpq's authority early, but the
    " whole string still reaches psql's command line. Refuse it too.
    return 1
  endif
  " vim-dadbod may hand the path to psql on its own, where it is conninfo.
  let path = matchstr(rest, '^[^/]*/\zs.*')
  return s:query_has_password(query)
        \ || s:conninfo_has_password(path) || s:conninfo_has_password(s:decode(path))
endfunction

" Does this connection string, or anything vim-dadbod derives from it for
" psql, carry a password? Both checks call this one function.
function! s:carries_password(str) abort
  if type(a:str) != v:t_string || empty(a:str)
    return 0
  endif
  " Backstop: a password keyword anywhere once decoded.
  if s:decode(a:str) =~# '\c\%(^\|[^[:alnum:]_]\)password\s*='
    return 1
  endif
  if a:str =~? '^postgres\%(ql\)\=://'
    return s:uri_has_password(a:str)
  endif
  " vim-dadbod's opaque form, <scheme>:<rest>, or a bare URI or conninfo
  " string as psql's --dbname.
  let rest = a:str =~# '^[[:alnum:].+-]\+:' ? matchstr(a:str, '^[^:]*:\zs.*') : a:str
  if rest =~? '^postgres\%(ql\)\=://'
    return s:uri_has_password(rest)
  elseif rest =~# '^//'
    return s:uri_has_password('postgresql:' . rest)
  endif
  let query = matchstr(rest, '?\zs.*')
  let rest = substitute(rest, '?.*', '', '')
  return s:query_has_password(query)
        \ || s:conninfo_has_password(rest) || s:conninfo_has_password(s:decode(rest))
endfunction

function! s:refuse_password(url) abort
  if s:carries_password(a:url)
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
  " The arguments psql will actually get (all but SQL text after -c) pass the
  " same classifier, so no rewrite inside a builder can slip one through.
  for i in range(len(a:cmd))
    if (i == 0 || a:cmd[i - 1] !=# '-c') && s:carries_password(a:cmd[i])
      call s:refuse_password(a:cmd[i])
    endif
  endfor
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
