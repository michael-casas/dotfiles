" vim-dadbod's postgresql adapter, with psql run as `psql -X` so ~/.psqlrc
" (timing, borders, null display) stays out of Dadbod's results and out of the
" output Dadbod UI parses. Plain psql elsewhere still reads ~/.psqlrc.
"
" lua/plugins/dadbod.lua points g:db_adapter_postgresql and
" g:db_adapter_postgres here. Every function delegates to upstream; the ones
" that build a psql command line gain -X.

function! s:no_psqlrc(cmd) abort
  if type(a:cmd) != v:t_list || get(a:cmd, 0, '') !=# 'psql'
        \ || index(a:cmd, '-X') >= 0 || index(a:cmd, '--no-psqlrc') >= 0
    return a:cmd
  endif
  return [a:cmd[0], '-X'] + a:cmd[1:]
endfunction

function! envi#dadbod_postgresql#canonicalize(url) abort
  return db#adapter#postgresql#canonicalize(a:url)
endfunction

function! envi#dadbod_postgresql#interactive(url, ...) abort
  return s:no_psqlrc(call('db#adapter#postgresql#interactive', [a:url] + a:000))
endfunction

function! envi#dadbod_postgresql#filter(url) abort
  return s:no_psqlrc(db#adapter#postgresql#filter(a:url))
endfunction

function! envi#dadbod_postgresql#input(url, in) abort
  return s:no_psqlrc(db#adapter#postgresql#input(a:url, a:in))
endfunction

" These already pass --no-psqlrc upstream.
function! envi#dadbod_postgresql#complete_database(url) abort
  return db#adapter#postgresql#complete_database(a:url)
endfunction

function! envi#dadbod_postgresql#complete_opaque(url) abort
  return db#adapter#postgresql#complete_opaque(a:url)
endfunction

function! envi#dadbod_postgresql#tables(url) abort
  return db#adapter#postgresql#tables(a:url)
endfunction
