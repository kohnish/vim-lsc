function! lsc#cursor#onMove() abort
  call lsc#diag#ShowDiagnostic()
  call lsc#diag#HighlightReferences(v:false)
endfunction

function! lsc#cursor#onWinEnter() abort
  call lsc#diag#HighlightReferences(v:false)
endfunction

function! lsc#cursor#showDiagnostic() abort
  if !get(g:, 'lsc_enable_diagnostics', v:true) | return | endif
  if !get(g:, 'lsc_diagnostic_highlights', v:true) | return | endif
  let l:diagnostic = lsc#diagnostics#underCursor()
  if has_key(l:diagnostic, 'message')
    let l:max_width = &columns - 1 " Avoid edge of terminal
    let l:has_ruler = &ruler &&
        \ (&laststatus == 0 || (&laststatus == 1 && winnr('$') < 2))
    if l:has_ruler | let l:max_width -= 18 | endif
    if &showcmd | let l:max_width -= 11 | endif
    let l:message = strtrans(l:diagnostic.message)
    if strdisplaywidth(l:message) > l:max_width
      let l:max_width -= 1 " 1 character for ellipsis
      let l:truncated = strcharpart(l:message, 0, l:max_width)
      " Trim by character until a satisfactory display width.
      while strdisplaywidth(l:truncated) > l:max_width
        let l:truncated = strcharpart(l:truncated, 0, strchars(l:truncated) - 1)
      endwhile
      echo l:truncated."\u2026"
    else
      echo l:message
    endif
  else
    echo ''
  endif
endfunction

function! lsc#cursor#onChangesFlushed() abort
  let l:mode = mode()
  if l:mode ==# 'n' || l:mode ==# 'no'
    call lsc#diag#HighlightReferences(v:false)
  endif
endfunction

function! lsc#cursor#clean() abort
  call lsc#diag#Clean()
endfunction
