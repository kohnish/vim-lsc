let s:popup_id = 0

function! lsc#reference#goToDefinition(mods, issplit) abort
  call lsc#common#FileFlushChanges()
  call lsc#server#userCall('textDocument/definition',
      \ lsc#params#documentPosition(),
      \ lsc#common#GateResult('GoToDefinition', { msg -> s:GoToDefinition(a:mods, a:issplit, msg) }, function('lsc#common#GatedOnSkipCb'))
      \ )
endfunction

function! s:TryUpdateLocationFromLocList(location) abort
  if !has_key(a:location, "uri") && has_key(a:location, "targetUri")
      let a:location["uri"] = a:location["targetUri"]
  endif
  if !has_key(a:location, "range") && has_key(a:location, "targetSelectionRange")
      let a:location["range"] = a:location["targetSelectionRange"]
  endif
endfunction

function! s:GoToDefinition(mods, issplit, result) abort
  if !has_key(a:result, "result")
    call lsc#message#error('No definition response')
    return
  endif
  let l:results = a:result["result"]
  if l:results == v:null || len(l:results) == 0
      call lsc#message#error('No definition found')
      return
  endif

  if len(l:results) > 1
    call s:setQuickFixLocations("definitions", a:result)
    return
  endif

  let l:location = l:results[0]
  call s:TryUpdateLocationFromLocList(l:location)

  let l:file = lsc#uri#documentPath(l:location.uri)
  let l:line = l:location.range.start.line + 1
  let l:character = l:location.range.start.character + 1
  let l:dotag = &tagstack && exists('*gettagstack') && exists('*settagstack')
  if l:dotag
    let l:from = [bufnr('%'), line('.'), col('.'), 0]
    let l:tagname = expand('<cword>')
    let l:stack = gettagstack()
    if l:stack.curidx > 1
      let l:stack.items = l:stack.items[0:l:stack.curidx-2]
    else
      let l:stack.items = []
    endif
    let l:stack.items += [{'from': l:from, 'tagname': l:tagname}]
    let l:stack.curidx = len(l:stack.items)
    call settagstack(win_getid(), l:stack)
  endif
  call s:goTo(l:file, l:line, l:character, a:mods, a:issplit)
  if l:dotag
    let l:curidx = gettagstack().curidx + 1
    call settagstack(win_getid(), {'curidx': l:curidx})
  endif
endfunction


function! lsc#reference#findReferences() abort
  call lsc#common#FileFlushChanges()
  let l:params = lsc#params#documentPosition()
  let l:params.context = {'includeDeclaration': v:true}
  call lsc#server#userCall('textDocument/references', l:params,
      \ function('<SID>setQuickFixLocations', ['references']))
endfunction

function! lsc#reference#findImplementations() abort
  call lsc#common#FileFlushChanges()
  call lsc#server#userCall('textDocument/implementation',
      \ lsc#params#documentPosition(),
      \ function('<SID>setQuickFixLocations', ['implementations']))
endfunction

function! s:setQuickFixLocations(label, results) abort
  if !has_key(a:results, "result") || empty(a:results["result"])
    call lsc#message#show('No '.a:label.' found')
    return
  endif
  call map(a:results["result"], {_, ref -> s:QuickFixItem(ref)})
  call sort(a:results["result"], 'lsc#util#compareQuickFixItems')
  call setqflist([], ' ', {'title': a:label , 'items': a:results["result"], 'quickfixtextfunc': 'lsc#common#QflistTrimRoot' })
  copen
endfunction

" Convert an LSP Location to a item suitable for the vim quickfix list.
"
" Both representations are dictionaries.
"
" Location:
" 'uri': file:// URI
" 'range': {'start': {'line', 'character'}, 'end': {'line', 'character'}}
"
" QuickFix Item: (as used)
" 'filename': file path if file is not open
" 'lnum': line number
" 'col': column number
" 'text': The content of the referenced line
"
" LSP line and column are zero-based, vim is one-based.
function! s:QuickFixItem(location) abort
  call s:TryUpdateLocationFromLocList(a:location)
  let l:item = {'lnum': a:location.range.start.line + 1,
      \ 'col': a:location.range.start.character + 1}
  let l:file_path = lsc#uri#documentPath(a:location.uri)
  let l:item.filename = fnamemodify(l:file_path, ':.')
  let l:bufnr = lsc#file#bufnr(l:file_path)
  if l:bufnr != -1 && bufloaded(l:bufnr)
    let l:item.text = getbufline(l:bufnr, l:item.lnum)[0]
  else
    let l:item.text = readfile(l:file_path, '', l:item.lnum)[l:item.lnum - 1]
  endif
  return l:item
endfunction

function! s:goTo(file, line, character, mods, issplit) abort
  if exists('g:lsc_focus_if_open') && g:lsc_focus_if_open
    call lsc#common#FocusIfOpen(a:file)
  endif
  let l:prev_buf = bufnr('%')
  if a:issplit || a:file !=# lsc#common#FullAbsPath()
    let l:cmd = 'edit'
    if &modified
      let l:cmd = 'vsplit'
    endif
    let l:relative_path = fnamemodify(a:file, ':~:.')
    exec a:mods l:cmd fnameescape(l:relative_path)
  endif
  if l:prev_buf != bufnr('%')
    " switching buffers already left a jump
    " Set curswant manually to work around vim bug
    call cursor([a:line, a:character, 0, virtcol([a:line, a:character])])
    redraw
  else
    " Move with 'G' to ensure a jump is left
    exec 'normal! '.a:line.'G'
    " Set curswant manually to work around vim bug
    call cursor([0, a:character, 0, virtcol([a:line, a:character])])
  endif
endfunction

function! lsc#reference#hover() abort
  call lsc#common#FileFlushChanges()
  let l:params = lsc#params#documentPosition()
  call lsc#server#userCall('textDocument/hover', l:params,
      \ function('<SID>showHover', [s:hasOpenHover()]))
endfunction

function! s:hasOpenHover() abort
  if s:popup_id == 0 | return v:false | endif
  return len(popup_getoptions(s:popup_id)) > 0
endfunction

function! s:showHover(force_preview, msg) abort
  let l:result = a:msg["result"]
  if empty(l:result) || empty(l:result.contents)
    call lsc#message#error('No hover information found')
    return
  endif
  let l:contents = l:result.contents
  if type(l:contents) != type([])
    let l:contents = [l:contents]
  endif
  let l:lines = []
  let l:filetype = 'markdown'
  for l:item in l:contents
    if type(l:item) == type({})
      let l:lines += split(l:item.value, "\n")
      if has_key(l:item, 'language')
        let l:filetype = l:item.language
      elseif has_key(l:item, 'kind')
        let l:filetype = l:item.kind ==# 'markdown' ? 'markdown' : 'text'
      endif
    else
      let l:lines += split(l:item, "\n")
    endif
  endfor
  let b:lsc_last_hover = l:lines
  if get(g:, 'lsc_hover_popup', v:true) && (exists('*popup_atcursor')
    call s:closeHoverPopup()
    if (a:force_preview)
      call lsc#util#displayAsPreview(l:lines, l:filetype,
          \ function('lsc#util#noop'))
    else
      call s:openHoverPopup(l:lines, l:filetype)
    endif
  else
    call lsc#util#displayAsPreview(l:lines, l:filetype,
        \ function('lsc#util#noop'))
  endif
endfunction

function! s:openHoverPopup(lines, filetype) abort
  if len(a:lines) == 0 | return | endif
  let s:popup_id = popup_atcursor(a:lines, {
        \ 'padding': [1, 1, 1, 1],
        \ 'border': [0, 0, 0, 0],
        \ 'moved': 'any',
        \ })
  if g:lsc_enable_popup_syntax
    call setbufvar(winbufnr(s:popup_id), '&filetype', a:filetype)
  endif
endfunction

function! s:closeHoverPopup() abort
  call popup_close(s:popup_id)
  let s:popup_id = 0
endfunction

" Request a list of symbols in the current document and populate the quickfix
" list.
function! lsc#reference#documentSymbols() abort
  call lsc#common#FileFlushChanges()
  call lsc#server#userCall('textDocument/documentSymbol',
      \ lsc#params#textDocument(),
      \ function('<SID>setQuickFixSymbols'))
endfunction

function! s:setQuickFixSymbols(msg) abort
  let l:results = a:msg["result"]
  if empty(l:results)
    call lsc#message#show('No symbols found')
    return
  endif

  call map(l:results, {_, symbol -> lsc#convert#quickFixSymbol(symbol)})
  call sort(l:results, 'lsc#util#compareQuickFixItems')
  call setqflist(l:results)
  copen
endfunction
