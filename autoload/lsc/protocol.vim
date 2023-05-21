if !exists('s:initialized')
  let s:log_size = 10
  let s:initialized = v:true
endif

function! lsc#protocol#job_start(command, Callback, ErrCallback, OnExit) abort
  let l:c = {}
  let l:job_options = {'in_mode': 'lsp',
      \ 'out_mode': 'lsp',
      \ 'out_cb': {_, message -> a:Callback(message)},
      \ 'err_io': 'pipe', 'err_mode': 'nl',
      \ 'err_cb': {_, message -> a:ErrCallback(message)},
      \ 'exit_cb': {_, __ -> a:OnExit()}}
  let l:job = job_start(a:command, l:job_options)
  " call ch_logfile("/var/tmp/t", "w")
  let l:c.job_id = l:job
  let l:c._channel = job_getchannel(l:job)

  return l:c
endfunction

function! lsc#protocol#open(command, on_message, on_err, on_exit) abort
  let l:c = {
      \ '_call_id': 0,
      \ '_in': [],
      \ '_out': [],
      \ '_buffer': [],
      \ '_on_message': a:on_message,
      \ '_callbacks': {},
      \}
  function! l:c.request(method, params, callback, options) abort
    let l:message = s:Format(a:method, a:params, l:self._call_id)
    call ch_sendexpr(l:self._channel._channel, l:message, {"callback": {channel, msg -> a:callback(msg)}})
  endfunction
  function! l:c.notify(method, params) abort
    let l:message = s:Format(a:method, a:params, v:null)
    call ch_sendexpr(l:self._channel._channel, l:message)
  endfunction
  function! l:c.respond(id, result) abort
    call ch_sendexpr(l:self._channel._channel, {'id': a:id, 'result': a:result})
  endfunction
  function! l:c._receive(message) abort
    call lsc#common#Dispatch(a:message, l:self._on_message, {})
  endfunction
  let l:channel = lsc#protocol#job_start(a:command, l:c._receive, a:on_err, a:on_exit)
  if type(l:channel) == type(v:null)
    return v:null
  endif
  let l:c._channel = l:channel
  return l:c
endfunction

function! s:Format(method, params, id) abort
  let l:message = {'method': a:method}
  if type(a:params) != type(v:null) | let l:message['params'] = a:params | endif
  if type(a:id) != type(v:null) | let l:message['id'] = a:id | endif
  return l:message
endfunction
