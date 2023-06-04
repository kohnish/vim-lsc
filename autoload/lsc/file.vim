let s:file_versions = {}
let s:file_content = {}
let s:normalized_paths = {}

function lsc#file#file_versions() abort
    return s:file_versions
endfunction

function lsc#file#file_content() abort
    return s:file_content
endfunction

" Send a 'didOpen' message for all open buffers with a tracked file type for a
" running server.
function! lsc#file#trackAll(server) abort
  for l:buffer in getbufinfo({'bufloaded': v:true})
    if !getbufvar(l:buffer.bufnr, '&modifiable') | continue | endif
    if  l:buffer.name =~# '\vfugitive:///' | continue | endif
    let l:filetype = getbufvar(l:buffer.bufnr, '&filetype')
    if index(a:server.filetypes, l:filetype) < 0 | continue | endif
    call lsc#file#track(a:server, l:buffer, l:filetype)
  endfor
endfunction

function! lsc#file#track(server, buffer, filetype) abort
  let l:file_path = lsc#file#normalize(a:buffer.name)
  call s:DidOpen(a:server, a:buffer.bufnr, l:file_path, a:filetype)
endfunction

" Run language servers for this filetype if they aren't already running and
" flush file changes.
function! lsc#file#onOpen() abort
  let l:file_path = lsc#common#FullAbsPath()
  if has_key(s:file_versions, l:file_path)
    call lsc#common#FileFlushChanges()
  else
    let l:bufnr = bufnr('%')
    let l:server = lsc#server#forFileType(&filetype)
    if !get(l:server.config, 'enabled', v:true) | continue | endif
    if ch_status(l:server.channel) == "open"
      call s:DidOpen(l:server, l:bufnr, l:file_path, &filetype)
    else
      call lsc#server#start(l:server)
    endif
  endif
endfunction

function! lsc#file#onClose(full_path, filetype) abort
  if has_key(s:file_versions, a:full_path)
    unlet s:file_versions[a:full_path]
  endif
  if has_key(s:file_content, a:full_path)
    unlet s:file_content[a:full_path]
  endif
  if !lsc#server#filetypeActive(a:filetype) | return | endif
  let l:params = {'textDocument': {'uri': lsc#uri#documentUri(a:full_path)}}
  let l:server = lsc#server#forFileType(a:filetype)
  call lsc#common#Publish(l:server.channel, 'textDocument/didClose', l:params)
endfunction

" Send a `textDocument/didSave` notification if the server may be interested.
function! lsc#file#onWrite(full_path, filetype) abort
  let l:params = {'textDocument': {'uri': lsc#uri#documentUri(a:full_path)}}
  let l:server = lsc#server#forFileType(a:filetype)
  if l:server.capabilities.textDocumentSync.sendDidSave
    call lsc#common#Publish(l:server.channel, 'textDocument/didSave', l:params)
  endif
endfunction

" Send the 'didOpen' message for a file.
function! s:DidOpen(server, bufnr, file_path, filetype) abort
  let l:buffer_content = has_key(s:file_content, a:file_path)
      \ ? s:file_content[a:file_path]
      \ : getbufline(a:bufnr, 1, '$')
  let l:version = has_key(s:file_versions, a:file_path)
      \ ? s:file_versions[a:file_path]
      \ : 1
  let l:params = {'textDocument':
      \   {'uri': lsc#uri#documentUri(a:file_path),
      \    'version': l:version,
      \    'text': join(l:buffer_content, "\n") .. "\n",
      \    'languageId': a:server.languageId[a:filetype],
      \   }
      \ }
  call lsc#common#Publish(a:server.channel, 'textDocument/didOpen', l:params)
  let s:file_versions[a:file_path] = l:version
  if get(g:, 'lsc_enable_incremental_sync', v:true) && a:server.capabilities.textDocumentSync.incremental
    let s:file_content[a:file_path] = l:buffer_content
  endif
  doautocmd <nomodeline> User LSCOnChangesFlushed
endfunction

" Mark all files of type `filetype` as untracked.
function! lsc#file#clean(filetype) abort
  for l:buffer in getbufinfo({'bufloaded': v:true})
    if getbufvar(l:buffer.bufnr, '&filetype') != a:filetype | continue | endif
    if has_key(s:file_versions, l:buffer.name)
      unlet s:file_versions[l:buffer.name]
      if has_key(s:file_content, l:buffer.name)
        unlet s:file_content[l:buffer.name]
      endif
    endif
  endfor
endfunction

function! lsc#file#version() abort
  return get(s:file_versions, lsc#common#FullAbsPath(), '')
endfunction

" Like `bufnr()` but handles the case where a relative path was normalized
" against cwd.
function! lsc#file#bufnr(full_path) abort
  let l:bufnr = bufnr(a:full_path)
  if l:bufnr == -1 && has_key(s:normalized_paths, a:full_path)
    let l:bufnr = bufnr(s:normalized_paths[a:full_path])
  endif
  return l:bufnr
endfunction

" Normalize `original_path` for OS separators and relative paths, and store the
" mapping.
"
" The return value is always a full path, even if vim won't expand it with `:p`
" because it is in a non-existent directory. The original path is stored, keyed
" by the normalized path, so that it can be retrieved by `lsc#file#bufnr`.
function! lsc#file#normalize(original_path) abort
  let l:full_path = a:original_path
  if l:full_path !~# '^/\|\%([c-zC-Z]:[/\\]\)'
    let l:full_path = getcwd().'/'.l:full_path
  endif
  let l:full_path = s:os_normalize(l:full_path)
  let s:normalized_paths[l:full_path] = a:original_path
  return l:full_path
endfunction

function! lsc#file#compare(file_1, file_2) abort
  if a:file_1 == a:file_2 | return 0 | endif
  let l:cwd = '^'.s:os_normalize(getcwd())
  let l:file_1_in_cwd = a:file_1 =~# l:cwd
  let l:file_2_in_cwd = a:file_2 =~# l:cwd
  if l:file_1_in_cwd && !l:file_2_in_cwd | return -1 | endif
  if l:file_2_in_cwd && !l:file_1_in_cwd | return 1 | endif
  return a:file_1 > a:file_2 ? 1 : -1
endfunction

" `getcwd` with OS path normalization.
function! lsc#file#cwd() abort
  return s:os_normalize(getcwd())
endfunction

function! s:os_normalize(path) abort
  if has('win32') | return substitute(a:path, '\\', '/', 'g') | endif
  return a:path
endfunction
