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
  call l:server.request('textDocument/signatureHelp', l:params,
      \ lsc#util#gateResult('SignatureHelp', function('<SID>ShowHelp')))
endfunction

function! s:HighlightCurrentParameter() abort
  execute 'match lscCurrentParameter /\V' . s:current_parameter . '/'
endfunction

function! s:ShowHelp(signatureHelp) abort
  if empty(a:signatureHelp)
    call lsc#message#show('No signature help available')
    return
  endif
  let l:signatures = []
  if has_key(a:signatureHelp, 'signatures')
    if type(a:signatureHelp.signatures) == type([])
      let l:signatures = a:signatureHelp.signatures
    endif
  endif

  if len(l:signatures) == 0
    return
  endif

  let l:active_signature = 0
  if has_key(a:signatureHelp, 'activeSignature')
    let l:active_signature = a:signatureHelp.activeSignature
    if l:active_signature >= len(l:signatures)
      let l:active_signature = 0
    endif
  endif

  let l:signature = get(l:signatures, l:active_signature)

  if !has_key(l:signature, 'label')
    return
  endif

  if !has_key(l:signature, 'parameters')
      call popup_close(s:popup_id)
      let s:popup_id = popup_atcursor(l:signature.label, {})
      "call lsc#util#displayAsPreview([l:signature.label], &filetype, function('<SID>HighlightCurrentParameter'))
      return
  endif

  let s:active_param_len = 0
  if has_key(a:signatureHelp, 'activeParameter')
    let l:active_parameter = a:signatureHelp.activeParameter
    if l:active_parameter < len(l:signature.parameters) && has_key(l:signature.parameters[l:active_parameter], 'label')
      let s:current_parameter = l:signature.parameters[l:active_parameter].label
      let s:active_param_len = len(s:current_parameter)
      let s:active_param_start_pos = stridx(l:signature.label, s:current_parameter) + 1
    endif
  endif
  call popup_close(s:popup_id)
  let s:popup_id = popup_atcursor(l:signature.label, {})
  let popup_win_id = winbufnr(s:popup_id)
  call prop_type_delete('signature')
  call prop_type_add('signature', {'bufnr': popup_win_id ,'highlight': 'PmenuSel'})
  if s:active_param_len > 0
      call prop_add(1, s:active_param_start_pos, {'bufnr': popup_win_id, 'type': 'signature', 'length': s:active_param_len})
  endif
  "call lsc#util#displayAsPreview([l:signature.label], &filetype,
  "    \ function('<SID>HighlightCurrentParameter'))

endfunction
