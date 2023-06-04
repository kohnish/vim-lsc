let s:servers = {}

function! s:BuffersOfType(filetype) abort
  let l:buffers = []
  for l:buffer in getbufinfo({'bufloaded': v:true})
    if getbufvar(l:buffer.bufnr, '&filetype') == a:filetype &&
        \ getbufvar(l:buffer.bufnr, '&modifiable') &&
        \ l:buffer.name !~# '\v^fugitive:///'
      call add(l:buffers, l:buffer)
    endif
  endfor
  return l:buffers
endfunction

function lsc#server#server_null() abort
    return {
      \ 'filetypes': [],
      \ 'languageId': {},
      \ 'config': {},
      \ 'capabilities': {},
      \ 'channel': lsc#common#NullChannel()
      \}
endfunction

" RegisterLanguageServer
"
" Registers a command as the server to start the first time a file with type
" filetype is seen. As long as the server is running it won't be restarted on
" subsequent appearances of this file type. If the server exits it will be
" restarted the next time a window or tab is entered with this file type.
function! lsc#server#RegisterLanguageServer(filetype, config) abort
  let l:server = lsc#server#register(a:filetype, a:config)
  if !get(l:server.config, 'enabled', v:true) | return | endif
  let l:buffers = s:BuffersOfType(a:filetype)
  if empty(l:buffers) | return | endif
  if ch_status(l:server.channel) == "open"
    for l:buffer in l:buffers
      call lsc#file#track(l:server, l:buffer, a:filetype)
    endfor
  else
    call lsc#server#start(l:server)
  endif
endfunction

function! s:LSCServerRegister()
    let cfg = {}
    if exists('g:lsc_server_commands')
      let cfg = g:lsc_server_commands
    endif
    for [s:filetype, s:config] in items(cfg)
        if type(s:config) == type({}) || type(s:config) == type({_ -> _}) || executable(split(s:config)[0])
            call lsc#server#RegisterLanguageServer(s:filetype, s:config)
        endif
    endfor
endfunction

function s:Get_workspace_config(config, item) abort
  if !has_key(a:config, 'workspace_config') | return v:null | endif
  if !has_key(a:item, 'section') || empty(a:item.section)
    return a:config.workspace_config
  endif
  let l:workspace_config = a:config.workspace_config
  for l:part in split(a:item.section, '\.')
    if !has_key(l:workspace_config, l:part)
      return v:null
    else
      let l:workspace_config = l:workspace_config[l:part]
    endif
  endfor
  return l:workspace_config
endfunction

function! s:Server_print_error(message, config) abort
  if get(a:config, 'suppress_stderr', v:false) | return | endif
  call lsc#message#error('StdErr from ' .. a:config.name .. a:message)
endfunction

function! lsc#server#proj_root() abort
  let l:proj_root = getcwd()
  if exists('g:lsc_get_proj_root_func') && g:lsc_get_proj_root_func
    let l:user_proj_root = LSClientGetProjRootFunc()
    if !empty(l:user_proj_root)
        let l:proj_root = l:user_proj_root
    endif
  endif
  return l:proj_root
endfunction

function! lsc#server#start(server) abort
  call s:Start(a:server, lsc#server#proj_root())
endfunction

function! lsc#server#servers() abort
  return s:servers
endfunction

function! lsc#server#forFileType(filetype) abort
  try
    return s:servers[g:lsc_servers_by_filetype[a:filetype]]
  catch
  endtry
  return lsc#server#server_null()
endfunction

function! s:ExitServer(channel, msg)
    call lsc#common#Publish(a:channel, "exit", {})
endfunction

function! s:RestartOrDisable(do_restart)
  if a:do_restart
      let g:lsc_disabled = 0
      call lsc#config#mapKeys()
      call s:LSCServerRegister()
  else
      let g:lsc_disabled = 1
      call lsc#config#UnmapKeys()
      call lsc#message#log("vim-lsc has been disabled", 3)
  endif
endfunction

function! s:CheckExit(servers, exit_start, do_restart, timer_id)
  let l:max_wait =  get(g:, 'lsc_max_exit_wait_sec_float', 3.0)
  for l:server in values(s:servers)
      if ch_status(l:server.channel) == "open" && reltimefloat(reltime(a:exit_start)) <= l:max_wait
          call timer_start(100, funcref('<SID>CheckExit', [s:servers, a:exit_start, a:do_restart]))
          return
      endif
  endfor
  for l:server in values(s:servers)
      if ch_status(l:server.channel) == "open"
          call lsc#message#error("Forcing shutdown")
          let l:job_id = ch_getjob(l:server.channel)
          if (job_status(l:job_id) == "run")
            call job_stop(l:job_id, "kill")
          endif
      endif
  endfor
  call timer_start(100, {_ -> s:RestartOrDisable(a:do_restart)})
endfunction

" Wait for all running servers to shut down with a 5 second timeout.
function! lsc#server#exit(do_restart) abort
  let l:sent = v:false
  for l:server in values(s:servers)
      if ch_status(l:server.channel) == "open"
           call lsc#common#Send(l:server.channel, 'shutdown', {}, funcref('<SID>ExitServer', [l:server.channel]))
           let l:sent = v:true
      endif
  endfor

  if l:sent
    call timer_start(0, funcref('<SID>CheckExit', [s:servers, reltime(), a:do_restart]))
  else
    call s:RestartOrDisable(a:do_restart)
  endif
endfunction

function! lsc#server#userCall(method, params, callback) abort
  let l:server = lsc#server#forFileType(&filetype)
  if ch_status(l:server.channel) == "open"
    call lsc#common#Send(l:server.channel, a:method, a:params, a:callback)
  else
    call lsc#message#log("Language server is not running", 3)
  endif
endfunction

" Start `server` if it isn't already running.
function! s:Start(server, root_dir) abort
  if ch_status(a:server.channel) == "open"
    call lsc#message#log("Server is already running", 3)
    return
  endif
  if type(a:server.config.command) == type({_ -> _})
    let l:command = a:server.config.command()
  else
    let l:command = a:server.config.command
  endif

  let l:exec = split(l:command)[0]
  if !executable(l:exec)
      return
  endif

  let a:server.channel = job_getchannel(job_start(l:command, {
              \ 'in_mode': 'lsp',
              \ 'out_mode': 'lsp',
              \ 'err_io': 'pipe',
              \ 'err_mode': 'nl',
              \ 'noblock': 1,
              \ 'out_cb': {_, lsp_message -> s:Dispatch(a:server, lsp_message)},
              \ 'err_cb': {_, lsp_err_msg -> s:Server_print_error(lsp_err_msg, a:server.config)},
              \ 'exit_cb': {_,__ -> lsc#common#Buffers_reset_state(a:server.filetypes)}
              \ }
              \ ))
  if string(a:server.channel) == 'channel fail'
    return
  endif

  if exists('g:lsc_trace_level') && index(['off', 'messages', 'verbose'], g:lsc_trace_level) >= 0
    let l:trace_level = g:lsc_trace_level
  else
    let l:trace_level = 'off'
  endif
  let l:params = {'processId': getpid(),
      \ 'clientInfo': {'name': 'vim-lsc'},
      \ 'rootUri': lsc#uri#documentUri(a:root_dir),
      \ 'capabilities': s:ClientCapabilities(),
      \ 'trace': l:trace_level
      \}
  let l:params = lsc#config#messageHook(a:server, 'initialize', l:params)
  call lsc#common#Send(a:server.channel, 'initialize', l:params, funcref('<SID>OnInitialize', [a:server]))
endfunction

function! s:OnInitialize(server, init_result) abort
  let l:result = a:init_result["result"]
  call lsc#common#Publish(a:server.channel, 'initialized', {})
  if has_key(l:result, 'capabilities')
    let a:server.capabilities = lsc#capabilities#normalize(l:result.capabilities)
  endif
  if has_key(a:server.config, 'workspace_config')
    call lsc#common#Publish(a:server.channel, 'workspace/didChangeConfiguration', {
        \ 'settings': a:server.config.workspace_config
        \})
  endif
  call lsc#file#trackAll(a:server)
  call lsc#message#log(a:server.config.name .. " is ready", 3)
endfunction

" Missing value means no support
function! s:ClientCapabilities() abort
  let l:applyEdit = v:false
  if !exists('g:lsc_enable_apply_edit') || g:lsc_enable_apply_edit
    let l:applyEdit = v:true
  endif
  return {
    \ 'workspace': {
    \   'applyEdit': l:applyEdit,
    \   'configuration': v:true,
    \ },
    \ 'textDocument': {
    \   'synchronization': {
    \     'willSave': v:false,
    \     'willSaveWaitUntil': v:false,
    \     'didSave': v:false,
    \   },
    \   'completion': {
    \     'completionItem': {
    \       'snippetSupport': g:lsc_enable_snippet_support,
    \       'deprecatedSupport': v:true,
    \       'tagSupport': {
    \         'valueSet': [1],
    \       },
    \      },
    \   },
    \   'definition': {'dynamicRegistration': v:false},
    \   'codeAction': {
    \     'codeActionLiteralSupport': {
    \       'codeActionKind': {'valueSet': ['quickfix', 'refactor', 'source']}
    \     }
    \   },
    \   'hover': {'contentFormat': ['plaintext', 'markdown']},
    \   'signatureHelp': {'dynamicRegistration': v:false},
    \ },
    \ 'offsetEncoding': ['utf-8'],
    \}
endfunction
    " \ 'workspace': {
    " \   'applyEdit': l:applyEdit,
    " \   'configuration': v:true,
    " \ },
    " \ 'general': {
    " \    'positionEncodings': ['utf-8']
    " \ },
    " \ 'textDocument': {
    " \   'synchronization': {
    " \     'willSave': v:false,
    " \     'willSaveWaitUntil': v:false,
    " \     'didSave': v:false,
    " \   },
    " \   'completion': {
    " \     'completionItem': {
    " \       'snippetSupport': g:lsc_enable_snippet_support,
    " \       'deprecatedSupport': v:true,
    " \       'tagSupport': {
    " \         'valueSet': [1],
    " \       },
    " \      },
    " \   },
    " \   'definition': {'dynamicRegistration': v:false},
    " \   'codeAction': {
    " \     'codeActionLiteralSupport': {
    " \       'codeActionKind': {'valueSet': ['quickfix', 'refactor', 'source']}
    " \     }
    " \   },
    " \   'hover': {'contentFormat': ['plaintext', 'markdown']},
    " \   'signatureHelp': {'dynamicRegistration': v:false},
    " \ },
    " \ 'offsetEncoding': ['utf-8'],
    " \}

function! lsc#server#filetypeActive(filetype) abort
  try
    let l:server = s:servers[g:lsc_servers_by_filetype[a:filetype]]
    return get(l:server.config, 'enabled', v:true)
  catch
    return v:false
  endtry
endfunction

function! lsc#server#register(filetype, config) abort
  let l:languageId = a:filetype

  if type(a:config) == type('')
    let l:config = {'command': a:config, 'name': a:config}
  elseif type(a:config) == type([])
    let l:config = {'command': a:config, 'name': string(a:config)}
  elseif type(a:config) == type({_ -> _})
    let l:config = {'command': a:config, 'name': a:config()}
  else
    if type(a:config) != type({})
      throw 'Server configuration must be an executable or a dict'
    endif
    let l:config = a:config
    if !has_key(l:config, 'command')
      throw 'Server configuration must have a "command" key'
    endif
    if !has_key(l:config, 'name')
      let l:config.name = string(l:config.command)
    endif
    if has_key(l:config, 'languageId')
      let l:languageId = l:config.languageId
    endif
  endif

  let g:lsc_servers_by_filetype[a:filetype] = l:config.name
  if has_key(s:servers, l:config.name)
    let l:server = s:servers[l:config.name]
    call add(l:server.filetypes, a:filetype)
    let l:server.languageId[a:filetype] = l:languageId
    return l:server
  endif

  let l:server = {
      \ 'filetypes': [a:filetype],
      \ 'languageId': {},
      \ 'config': l:config,
      \ 'capabilities': lsc#capabilities#defaults(),
      \ 'channel': lsc#common#NullChannel()
      \}
  let l:server.languageId[a:filetype] = l:languageId
  let s:servers[l:config.name] = l:server
  return l:server
endfunction

function! s:Dispatch(server, msg) abort
  let l:method = a:msg["method"]
  if l:method ==? 'textDocument/publishDiagnostics'
    let l:file_path = lsc#uri#documentPath(a:msg["params"]['uri'])
    call lsc#common#DiagnosticsSetForFile(l:file_path, a:msg["params"]['diagnostics'])
  elseif l:method ==? 'window/showMessage'
    call lsc#message#show(a:msg["params"]['message'], a:msg["params"]['type'])
  elseif l:method ==? 'window/showMessageRequest'
    let l:response =
        \ lsc#message#showRequest(a:msg["params"]['message'], a:msg["params"]['actions'])
    call lsc#common#Reply(a:server.channel, a:msg["id"], l:response)
  elseif l:method ==? 'window/logMessage'
    if lsc#config#shouldEcho(a:server, a:msg["params"].type)
      call lsc#message#log(a:msg["params"].message, a:msg["params"].type)
    endif
  elseif l:method ==? 'window/progress'
    if has_key(a:msg["params"], 'message')
      let l:full = a:msg["params"]['title'] . a:msg["params"]['message']
      call lsc#message#show('Progress ' . l:full)
    elseif has_key(a:msg["params"], 'done')
      call lsc#message#show('Finished ' . a:msg["params"]['title'])
    else
      call lsc#message#show('Starting ' . a:msg["params"]['title'])
    endif
  elseif l:method ==? 'workspace/applyEdit'
    let l:applied = lsc#edit#apply(a:msg["params"].edit)
    call lsc#common#Reply(a:server.channel, a:msg["id"], l:response)
  elseif l:method ==? 'workspace/configuration'
    let l:items = a:msg["params"].items
    let l:response = map(l:items, {_, item -> s:Get_workspace_config(a:server.config, item)})
    call lsc#common#Reply(a:server.channel, a:msg["id"], l:response)
  elseif l:method =~? '\v^\$'
    call lsc#config#handleNotification(a:server, l:method, a:msg["params"])
  endif
endfunction
