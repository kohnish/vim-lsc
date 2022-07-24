if !exists('s:initialized')
  let s:current_parameter = ''
  let s:initialized = v:true
  let s:popup_id = -1
endif

function! lsc#signaturehelp#getSignatureHelp() abort
  call lsc#file#flushChanges()
  let l:params = lsc#params#documentPosition()
  " TODO handle multiple servers
  let l:server = lsc#server#forFileType(&filetype)[0]
  try
    call l:server.request('textDocument/signatureHelp', l:params,
      \ lsc#util#gateResult('SignatureHelp', function('lsc#signature_help#ShowHelp')))
  catch
  endtry
endfunction

function! s:HighlightCurrentParameter() abort
  execute 'match lscCurrentParameter /\V' . s:current_parameter . '/'
endfunction
