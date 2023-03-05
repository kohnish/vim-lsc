if !exists('s:file_diagnostics')
    " file path -> Diagnostics
    "
    " Diagnostics are dictionaries with:
    " 'Highlights()': Highlight groups and ranges
    " 'ByLine()': Nested dictionaries with the structure:
    "     { line: [{
    "         message: Human readable message with code
    "         range: LSP Range object
    "         severity: String label for severity
    "       }]
    "     }
    " 'ListItems()': QuickFix or Location list items
    let s:file_diagnostics = {}
endif

function! lsc#diagnostics#clean(filetype) abort
    for l:buffer in getbufinfo({'bufloaded': v:true})
        if getbufvar(l:buffer.bufnr, '&filetype') != a:filetype | continue | endif
        call lsc#vim9#DiagnosticsSetForFile(lsc#file#normalize(l:buffer.name), [])
    endfor
endfunction

function! lsc#diagnostics#file_diagnostics() abort
    return s:file_diagnostics
endfunction

function! lsc#diagnostics#forFile(file_path) abort
    if !has_key(s:file_diagnostics, a:file_path)
        return s:EmptyDiagnostics()
    endif
    return s:file_diagnostics[a:file_path]
endfunction

function! lsc#diagnostics#echoForLine() abort
    let l:file_diagnostics = lsc#diagnostics#forFile(lsc#common#FullAbsPath()).ByLine()
    let l:line = line('.')
    if !has_key(l:file_diagnostics, l:line)
        echo 'No diagnostics'
        return
    endif
    let l:diagnostics = l:file_diagnostics[l:line]
    for l:diagnostic in l:diagnostics
        let l:label = '['.l:diagnostic.severity.']'
        if stridx(l:diagnostic.message, "\n") >= 0
            echo l:label
            echo l:diagnostic.message
        else
            echo l:label.': '.l:diagnostic.message
        endif
    endfor
endfunction

function! lsc#diagnostics#updateCurrentWindow() abort
    let l:diagnostics = lsc#diagnostics#forFile(lsc#common#FullAbsPath())
    if exists('w:lsc_diagnostics') && w:lsc_diagnostics is l:diagnostics
        return
    endif
    call s:UpdateWindowState(win_getid(), l:diagnostics)
endfunction

function! s:UpdateWindowState(window_id, diagnostics) abort
    call settabwinvar(0, a:window_id, 'lsc_diagnostics', a:diagnostics)
    let l:list_info = getloclist(a:window_id, {'changedtick': 1})
    let l:new_list = get(l:list_info, 'changedtick', 0) == 0
    if l:new_list
        call s:CreateLocationList(a:window_id, a:diagnostics.ListItems())
    else
        call s:UpdateLocationList(a:window_id, a:diagnostics.ListItems())
    endif
endfunction

function! s:CreateLocationList(window_id, items) abort
    call setloclist(a:window_id, [], ' ', {
                \ 'title': 'LSC Diagnostics',
                \ 'items': a:items,
                \})
    let l:new_id = getloclist(a:window_id, {'id': 0}).id
    call settabwinvar(0, a:window_id, 'lsc_location_list_id', l:new_id)
endfunction

" Update an existing location list to contain new items.
"
" If the LSC diagnostics location list is not reachable with `lolder` or
" `lhistory` the update will silently fail.
function! s:UpdateLocationList(window_id, items) abort
    let l:list_id = gettabwinvar(0, a:window_id, 'lsc_location_list_id', -1)
    call setloclist(a:window_id, [], 'r', {
                \ 'id': l:list_id,
                \ 'items': a:items,
                \})
endfunction

function! lsc#diagnostics#showLocationList() abort
    let l:window_id = win_getid()
    if &filetype ==# 'qf'
        let l:list_window = get(getloclist(0, {'filewinid': 0}), 'filewinid', 0)
        if l:list_window != 0
            let l:window_id = l:list_window
        endif
    endif
    let l:list_id = gettabwinvar(0, l:window_id, 'lsc_location_list_id', -1)
    if l:list_id != -1 && !s:SurfaceLocationList(l:list_id)
        let l:path = lsc#file#normalize(bufname(winbufnr(l:window_id)))
        let l:items = lsc#diagnostics#forFile(l:path).ListItems()
        call s:CreateLocationList(l:window_id, l:items)
    endif
    lopen
endfunction

" If the LSC maintained location list exists in the location list stack, switch
" to it and return true, otherwise return false.
function! s:SurfaceLocationList(list_id) abort
    let l:list_info = getloclist(0, {'nr': 0, 'id': a:list_id})
    let l:nr = get(l:list_info, 'nr', -1)
    if l:nr <= 0 | return v:false | endif

    let l:diff = getloclist(0, {'nr': 0}).nr - l:nr
    if l:diff == 0
        " already there
    elseif l:diff > 0
        execute 'lolder '.string(l:diff)
    else
        execute 'lnewer '.string(abs(l:diff))
    endif
    return v:true
endfunction

function! lsc#diagnostics#clear() abort
    if !empty(w:lsc_diagnostics.lsp_diagnostics)
        call s:UpdateLocationList(win_getid(), [])
    endif
    unlet w:lsc_diagnostics
endfunction

function! lsc#diagnostics#DiagObjCreate(file_path, lsp_diagnostics) abort
    return {
                \ 'lsp_diagnostics': a:lsp_diagnostics,
                \ 'Highlights': funcref('<SID>DiagnosticsHighlights'),
                \ 'ListItems': funcref('<SID>DiagnosticsListItems', [a:file_path]),
                \ 'ByLine': funcref('<SID>DiagnosticsByLine'),
                \ }
endfunction

function! s:EmptyDiagnostics() abort
    if !exists('s:empty_diagnostics')
        let s:empty_diagnostics = {
                    \ 'lsp_diagnostics': [],
                    \ 'Highlights': {->[]},
                    \ 'ListItems': {->[]},
                    \ 'ByLine': {->{}},
                    \}
    endif
    return s:empty_diagnostics
endfunction

function! lsc#diagnostics#underCursor() abort
    return lsc#diag#UnderCursor(lsc#diagnostics#forFile(lsc#common#FullAbsPath()).ByLine())
endfunction

function! lsc#diagnostics#forLine(file, line) abort
    return lsc#diag#ForLine(lsc#diagnostics#forFile(a:file).lsp_diagnostics, a:file, a:line)
endfunction

function! s:DiagnosticsHighlights() abort dict
    return lsc#diag#DiagnosticsHighlights(l:self)
endfunction

function! s:DiagnosticsListItems(file_path) abort dict
    return lsc#diag#DiagnosticsListItems(l:self, a:file_path)
endfunction

function! s:DiagnosticsByLine() abort dict
    return lsc#diag#DiagnosticsByLine(l:self)
endfunction
