" Use InsertCharPre to reliably know what is typed, but don't send the
" completion request until the file reflects the inserted character. Track typed
" characters in `s:next_char` and use CursorMovedI to act on the change.
"
" Every typed character can potentially start a completion request:
" - "Trigger" characters (as specified during initialization) always start a
"   completion request when they are typed
" - Characters that match '\w' start a completion in words of at least length 3

function! lsc#complete#insertCharPre() abort
  let s:next_char = v:char
endfunction

let s:sighelp_timer = -1
function! lsc#complete#sig_help_with_timer() abort
    call lsc#common#GetSignatureHelp()
    let s:sighelp_timer = -1
endfunction

function! lsc#complete#textChanged() abort
  if &paste | return | endif
  if !g:lsc_enable_autocomplete | return | endif
  " This may be <BS> or similar if not due to a character typed
  if empty(s:next_char) | return | endif
  call s:typedCharacter()
  let s:next_char = ''
  " Might help input becoming slower.
  if s:sighelp_timer == -1
      let s:sighelp_timer = timer_start(200, {_->lsc#complete#sig_help_with_timer()})
  endif
endfunction

function! s:typedCharacter() abort
  if lsc#common#IsCompletable()
    call s:startCompletion(v:true)
  endif
endfunction

if !exists('s:initialized')
  let s:next_char = ''
  let s:initialized = v:true
endif

" Clean state associated with a server.
function! lsc#complete#clean(filetype) abort
  for l:buffer in getbufinfo({'bufloaded': v:true})
    if getbufvar(l:buffer.bufnr, '&filetype') != a:filetype | continue | endif
    call setbufvar(l:buffer.bufnr, 'lsc_is_completing', v:false)
  endfor
endfunction

function! s:isTrigger(char) abort
  for l:server in lsc#server#current()
    if index(l:server.capabilities.completion.triggerCharacters, a:char) >= 0
      return v:true
    endif
  endfor
  return v:false
endfunction

augroup LscCompletion
  autocmd!
  autocmd CompleteDone * let b:lsc_is_completing = v:false
      \ | silent! unlet b:lsc_completion | let s:next_char = ''
augroup END

function! s:startCompletion(isAuto) abort
  let b:lsc_is_completing = v:true
  call lsc#file#flushChanges()
  let l:params = lsc#params#documentPosition()
  " TODO handle multiple servers
  let l:server = lsc#server#forFileType(&filetype)[0]
  " try
    call l:server.request('textDocument/completion', l:params,
        \ lsc#common#GateResult('Complete',
        \     function('<SID>OnResult', [a:isAuto]),
        \     [function('<SID>OnSkip', [bufnr('%')])]))
    " catch
  " endtry
endfunction

function! s:OnResult(isAuto, completion) abort
  let l:items = []
  if type(a:completion) == type([])
    let l:items = a:completion
  elseif type(a:completion) == type({})
    let l:items = a:completion.items
  endif
  if (a:isAuto)
    call s:SuggestCompletions(l:items)
  else
    let b:lsc_completion = l:items
  endif
endfunction

function! s:OnSkip(bufnr, completion) abort
  call setbufvar(a:bufnr, 'lsc_is_completing', v:false)
endfunction

function! s:SuggestCompletions(items) abort
  if mode() !=# 'i' || len(a:items) == 0
    let b:lsc_is_completing = v:false
    return
  endif
  let l:start = lsc#comp#FindStart(a:items)
  let l:base = l:start != col('.')
      \ ? getline('.')[l:start - 1:col('.') - 2]
      \ : ''
  let l:completion_items = lsc#comp#CompletionItems(l:base, a:items)
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

function! lsc#complete#complete(findstart, base) abort
  if a:findstart
    if !exists('b:lsc_completion')
      let l:searchStart = reltime()
      call s:startCompletion(v:false)
      let l:timeout = get(g:, 'lsc_complete_timeout', 5)
      while !exists('b:lsc_completion')
            \ && reltimefloat(reltime(l:searchStart)) <= l:timeout
        sleep 100m
      endwhile
      if !exists('b:lsc_completion') || len(b:lsc_completion) == 0
        return -3
      endif
      return  lsc#comp#FindStart(b:lsc_completion) - 1
    endif
  else
    " We'll get an error if b:lsc_completion doesn't exist, which is good,
    " we want to be vocal about such failures.
    return s:CompletionItems(a:base, b:lsc_completion)
  endif
endfunction
