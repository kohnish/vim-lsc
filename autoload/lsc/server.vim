if !exists('s:initialized')
  " server name -> server info.
  "
  " Server name defaults to the command string.
  "
  " Info contains:
  " - status. Possible statuses are:
  "   [disabled, not started,
  "    starting, running, restarting,
  "    exiting,  exited, unexpected exit, failed]
  " - capabilities. Configuration for client/server interaction.
  " - filetypes. List of filetypes handled by this server.
  " - logs. The last 100 logs from `window/logMessage`.
  " - config. Config dict. Contains:
  "   - name: Same as the key into `s:servers`
  "   - command: Executable
  "   - enabled: (optional) Whether the server should be started.
  "   - message_hooks: (optional) Functions call to override params
  "   - workspace_config: (optional) Arbitrary data to send as
  "     `workspace/didChangeConfiguration` settings on startup.
  let s:servers = {}
  let s:initialized = v:true
endif

function! lsc#server#start(server) abort
  let l:proj_root = getcwd()
  if exists('g:lsc_get_proj_root_func') && g:lsc_get_proj_root_func
    let l:user_proj_root = LSClientGetProjRootFunc()
    if !empty(l:user_proj_root)
        let l:proj_root = l:user_proj_root
    endif
  endif
  call s:Start(a:server, l:proj_root)
endfunction

function! lsc#server#status(filetype) abort
  return s:servers[g:lsc_servers_by_filetype[a:filetype]].status
endfunction

function! lsc#server#servers() abort
  return s:servers
endfunction

" Returns a list of the servers for the current filetype.
"
" For now there will only ever be 1 or no values in this list.
function! lsc#server#current() abort
  return lsc#server#forFileType(&filetype)
endfunction

" Returns a list of the servers for [filetype].
"
" For now there will only ever be 1 or no values in this list.
function! lsc#server#forFileType(filetype) abort
  if !has_key(g:lsc_servers_by_filetype, a:filetype) | return [] | endif
  return [s:servers[g:lsc_servers_by_filetype[a:filetype]]]
endfunction

" Wait for all running servers to shut down with a 5 second timeout.
function! lsc#server#exit() abort
  call lsc#common#CleanAllMatchs()
  let l:exit_start = reltime()
  let l:pending = []
  for l:server in values(s:servers)
      for l:filetype in l:server.filetypes
          call lsc#common#CleanAllForFile(l:filetype)
      endfor
      if s:Kill(l:server, 'exiting', funcref('<SID>OnExit', [l:server.config.name, l:pending]))
          call add(l:pending, l:server.config.name)
      endif
  endfor
  if len(l:pending) > 0
      echom "Shutting down " .. len(l:pending) .. " language server(s)"
      let l:reported = []
      while len(l:pending) > 0 && reltimefloat(reltime(l:exit_start)) <= 10.0
          if reltimefloat(reltime(l:exit_start)) >= 0.1 && l:pending != l:reported
              echo 'Waiting for language server exit: ' .. join(l:pending, ', ')
              let l:reported = copy(l:pending)
          endif
          sleep 1000m
      endwhile
      let l:len_servers = len(l:pending)
      if (l:len_servers) > 0
          echom "Failed to shut down " .. len(l:pending) .. " language server(s)"
          return v:false
      endif
      echom "Shutdown successful"
  endif
  return v:true
endfunction

function! s:OnExit(server_name, pending) abort
  call remove(a:pending, index(a:pending, a:server_name))
endfunction

" Request a 'shutdown' then 'exit'.
"
" Calls `OnExit` after the exit is requested. Returns `v:false` if no request
" was made because the server is not currently running.
function! s:Kill(server, status, OnExit) abort
    if has_key(a:server, "channel") && ch_status(a:server.channel) == "open"
         call lsc#common#Send(a:server.channel, 'shutdown', {}, funcref('<SID>HandleShutdownResponse', [a:server, a:status, a:OnExit]))
         return v:true
    endif
    return v:false
endfunction

function! s:HandleShutdownResponse(server, status, OnExit, result) abort
  let a:server.status = a:status
  if has_key(a:server, 'channel')
    call lsc#common#Publish(a:server.channel, "exit", {})
    let l:exit_start = reltime()
    while ch_status(a:server.channel) == "open" && reltimefloat(reltime(l:exit_start)) <= 3.0
        sleep 300m
    endwhile
    if ch_status(a:server.channel) == "open"
        echom "Force shutting down"
        let l:job_id = ch_getjob(a:server.channel)
        let l:channel = job_getchannel(l:job_id)
        if (l:channel == "open")
          call ch_close(l:channel)
        endif
        sleep 100ms
        if (job_status(l:job_id) == "run")
          call job_stop(l:job_id, "term")
        endif
        sleep 100ms
        if (job_status(l:job_id) == "run")
          call job_stop(l:job_id, "kill")
        endif
    endif
  endif
  call a:OnExit()
endfunction

function! lsc#server#clear() abort
  let s:servers = {}
  let s:initialized = v:false
endfunction

function! lsc#server#restart() abort
  call lsc#server#disable(v:true)
endfunction

function! lsc#server#open(command, On_message, On_err, On_exit) abort
  let l:job_options = {'in_mode': 'lsp',
      \ 'out_mode': 'lsp',
      \ 'noblock': 1,
      \ 'out_cb': {_, message -> a:On_message(message)},
      \ 'err_io': 'pipe', 'err_mode': 'nl',
      \ 'err_cb': {_, message -> a:On_err(message)},
      \ 'exit_cb': {_, __ -> a:On_exit()}}
  let l:job = job_start(a:command, l:job_options)
  " call ch_logfile("/var/tmp/t", "w")
  let l:channel = job_getchannel(l:job)

  if type(l:channel) == type(v:null)
    return v:null
  endif

  return l:channel
endfunction
" A server call explicitly initiated by the user for the current buffer.
"
" Expects the call to succeed and shows an error if it does not.
function! lsc#server#userCall(method, params, callback) abort
  " TODO handle multiple servers
  let l:server = lsc#server#forFileType(&filetype)[0]
  call lsc#common#Send(l:server.channel, a:method, a:params, a:callback)
endfunction

" Start `server` if it isn't already running.
function! s:Start(server, root_dir) abort
  if has_key(a:server, 'channel')
    " Server is already running
    return
  endif
  if type( a:server.config.command) == type({_ -> _})
    let l:command = a:server.config.command()
  else
    let l:command = a:server.config.command
  endif
  let a:server.status = 'starting'
  let l:ch = lsc#server#open(l:command,
      \ {lsp_message -> s:Dispatch(a:server, lsp_message)},
      \ a:server.on_err, a:server.on_exit)
  let a:server.channel = l:ch
  if type(a:server.channel) == type(v:null)
    let a:server.status = 'failed'
    return
  endif
  if exists('g:lsc_trace_level') &&
      \ index(['off', 'messages', 'verbose'], g:lsc_trace_level) >= 0
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
  call a:server._initialize(l:params, funcref('<SID>OnInitialize', [a:server]))
endfunction

function! s:OnInitialize(server, init_result) abort
  call lsc#common#ResetRestartCounter()
  let a:server.status = 'running'
  call a:server.notify('initialized', {})
  if type(a:init_result) == type({}) && has_key(a:init_result, 'capabilities')
    let a:server.capabilities =
        \ lsc#capabilities#normalize(a:init_result.capabilities)
  endif
  if has_key(a:server.config, 'workspace_config')
    call a:server.notify('workspace/didChangeConfiguration', {
        \ 'settings': a:server.config.workspace_config
        \})
  endif
  call lsc#file#trackAll(a:server)
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
    \ }
    \}
endfunction

function! lsc#server#filetypeActive(filetype) abort
  try
    let l:server = s:servers[g:lsc_servers_by_filetype[a:filetype]]
    return get(l:server.config, 'enabled', v:true)
  catch
    return v:false
  endtry
endfunction

function! lsc#server#kill(job_id, filetypes) abort
  let l:channel = job_getchannel(a:job_id)
  if (l:channel == "open")
    call ch_close(l:channel)
  endif
  if (job_status(a:job_id) == "run")
    call job_stop(a:job_id, "term")
  endif
endfunction

function! lsc#server#reset_start() abort
  call lsc#server#clear()
  call LSCServerRegister()
endfunction

function! lsc#server#disable(do_restart) abort
  call lsc#server#exit()
  " for l:server in values(s:servers)
  "   call l:server.notify('exit', {})
  "   if has_key(l:server, "channel")
  "       let l:job_id = ch_getjob(l:server.channel)
  "       let l:filetypes = l:server.filetypes
  "       call timer_start(100, {_->lsc#server#kill(l:job_id, l:filetypes)})
  "   endif
  " endfor
  if a:do_restart
    call timer_start(1000, {_->lsc#server#reset_start()})
  endif
endfunction

function! lsc#server#enable() abort
    call lsc#server#restart()
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
  let l:initial_status = 'not started'
  if !get(l:config, 'enabled', v:true)
    let l:initial_status = 'disabled'
  endif
  let l:server = {
      \ 'status': l:initial_status,
      \ 'logs': [],
      \ 'filetypes': [a:filetype],
      \ 'languageId': {},
      \ 'config': l:config,
      \ 'capabilities': lsc#capabilities#defaults()
      \}
  let l:server.languageId[a:filetype] = l:languageId
  function! l:server.notify(method, params) abort
    if l:self.status !=# 'running' | return v:false | endif
    let l:params = lsc#config#messageHook(l:self, a:method, a:params)
    if l:params is lsc#config#skip() | return v:false | endif
    call lsc#common#Publish(l:self.channel, a:method, l:params)
    return v:true
  endfunction
  function! l:server._initialize(params, callback) abort
    let l:params = lsc#config#messageHook(l:self, 'initialize', a:params)
    call lsc#common#Send(l:self.channel, 'initialize', l:params, a:callback)
  endfunction
  function! l:server.respond(id, result) abort
    call lsc#common#Reply(l:self.channel, a:id, a:result)
  endfunction
  function! l:server.on_err(message) abort
    if get(l:self.config, 'suppress_stderr', v:false) | return | endif
    call lsc#message#error('StdErr from '.l:self.config.name.': '.a:message)
  endfunction
  function! l:server.on_exit() abort
    let l:old_status = l:self.status
    if l:old_status ==# 'starting'
      let l:self.status= 'failed'
      let l:message = 'Failed to initialize server "'.l:self.config.name.'".'
      if l:self.config.name != string(l:self.config.command)
        let l:message .= ' Failing command is: '.string(l:self.config.command)
      endif
      call lsc#message#error(l:message)
    elseif l:old_status ==# 'exiting'
      let l:self.status= 'exited'
    elseif l:old_status ==# 'running'
      let l:self.status = 'unexpected exit'
      call lsc#message#error('Command exited unexpectedly: '.l:self.config.name)
    endif
    call lsc#common#CleanAllMatchs()
    for l:filetype in l:self.filetypes
      call lsc#common#CleanAllForFile(l:filetype)
    endfor
  endfunction
  function! l:server.find_config(item) abort
    if !has_key(l:self.config, 'workspace_config') | return v:null | endif
    if !has_key(a:item, 'section') || empty(a:item.section)
      return l:self.config.workspace_config
    endif
    let l:config = l:self.config.workspace_config
    for l:part in split(a:item.section, '\.')
      if !has_key(l:config, l:part)
        return v:null
      else
        let l:config = l:config[l:part]
      endif
    endfor
    return l:config
  endfunction
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
    call a:server.respond(a:msg["id"], l:response)
  elseif l:method ==? 'window/logMessage'
    if lsc#config#shouldEcho(a:server, a:msg["params"].type)
      call lsc#message#log(a:msg["params"].message, a:msg["params"].type)
    endif
    call lsc#util#shift(a:server.logs, 100,
        \ {'message': a:msg["params"].message, 'type': a:msg["params"].type})
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
    let l:response = {'applied': l:applied}
    call a:server.respond(a:msg["id"], l:response)
  elseif l:method ==? 'workspace/configuration'
    let l:items = a:msg["params"].items
    let l:response = map(l:items, {_, item -> a:server.find_config(item)})
    call a:server.respond(a:msg["id"], l:response)
  elseif l:method =~? '\v^\$'
    call lsc#config#handleNotification(a:server, l:method, a:msg["params"])
  endif
endfunction
