function! lsc#search#workspaceSymbol(...) abort
  if a:0 >= 1
    let l:query = a:1
  else
    let l:query = input('Search Workspace For: ')
  endif
  call lsc#server#userCall('workspace/symbol', {'query': l:query},
      \ function('<SID>setQuickFixSymbols'))
endfunction

function! s:setQuickFixSymbols(msg) abort
  let l:results = a:msg["result"]
  if type(l:results) != type([]) || len(l:results) == 0
    call lsc#message#show('No quick fix symbols found')
    return
  endif

  call map(l:results, {_, symbol -> lsc#convert#quickFixSymbol(symbol)})
  call sort(l:results, 'lsc#util#compareQuickFixItems')
  call setqflist(l:results)
  copen
endfunction
