" Clean state associated with a server.
function! lsc#complete#clean(filetype) abort
  for l:buffer in getbufinfo({'bufloaded': v:true})
    if getbufvar(l:buffer.bufnr, '&filetype') != a:filetype | continue | endif
    call setbufvar(l:buffer.bufnr, 'lsc_is_completing', v:false)
  endfor
endfunction

function! lsc#complete#OnResult(isAuto, completion) abort
  if !has_key(a:completion, "result") || type(a:completion.result) != type({})
    "lsc#message#error(a:completion)
    return
  endif
  let l:items = a:completion.result.items
  if (a:isAuto)
    call s:SuggestCompletions(l:items)
  else
    let b:lsc_completion = l:items
  endif
endfunction

function! lsc#complete#OnSkip(bufnr, completion) abort
  call setbufvar(a:bufnr, 'lsc_is_completing', v:false)
endfunction

function! s:SuggestCompletions(items) abort
  if mode() !=# 'i' || len(a:items) == 0
    let b:lsc_is_completing = v:false
    return
  endif
  let l:start = lsc#common#FindStart(a:items)
  let l:base = l:start != col('.')
      \ ? getline('.')[l:start - 1:col('.') - 2]
      \ : ''
  let l:completion_items = lsc#common#CompletionItems(l:base, a:items)
  call s:SetCompleteOpt()
  if exists('#User#LSCAutocomplete')
    doautocmd <nomodeline> User LSCAutocomplete
  endif
  call complete(l:start, l:completion_items)
endfunction

function! s:SetCompleteOpt() abort
  if type(g:lsc_auto_completeopt) == type('')
    " Set completeopt locally exactly like the user wants
    execute 'setl completeopt='.g:lsc_auto_completeopt
  elseif (type(g:lsc_auto_completeopt) == type(v:true)
      \ || type(g:lsc_auto_completeopt) == type(0))
      \ && g:lsc_auto_completeopt
    " Set the options that impact behavior for autocomplete use cases without
    " touching other like `preview`
    setl completeopt-=longest
    setl completeopt+=menu,menuone,noinsert
  endif
endfunction
