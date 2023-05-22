if !exists('s:initialized')
  let s:log_size = 10
  let s:initialized = v:true
endif

function! lsc#protocol#job_start(command, Callback, ErrCallback, OnExit) abort
  let l_c = {}
  let l:job_options = {'in_mode': 'lsp',
      \ 'out_mode': 'lsp',
      \ 'out_cb': {_, message -> a:Callback(message)},
      \ 'err_io': 'pipe', 'err_mode': 'nl',
      \ 'err_cb': {_, message -> a:ErrCallback(message)},
      \ 'exit_cb': {_, __ -> a:OnExit()}}
  let l:job = job_start(a:command, l:job_options)
  " call ch_logfile("/var/tmp/t", "w")
  let l_c.job_id = l:job
  let l_c.channel = job_getchannel(l:job)

  return l_c
endfunction

function! lsc#protocol#open(command, on_message, on_err, on_exit) abort
  let l:channel = lsc#protocol#job_start(a:command, a:on_message, a:on_err, a:on_exit)
  if type(l:channel) == type(v:null)
    return v:null
  endif

  let l:c = {
      \ 'channel' : l:channel.channel,
      \ 'job_id' : l:channel.job_id
      \ }

  function! l:c.request(method, params, callback, options) abort
    let l:message = s:Format(a:method, a:params)
    call ch_sendexpr(l:self.channel, l:message, {"callback": {channel, msg -> a:callback(msg)}})
  endfunction
  function! l:c.notify(method, params) abort
    let l:message = s:Format(a:method, a:params)
    call ch_sendexpr(l:self.channel, l:message)
  endfunction

  return l:c
endfunction

function! s:Format(method, params) abort
  let l:message = {'method': a:method}
  if type(a:params) != type(v:null) | let l:message['params'] = a:params | endif
  return l:message
endfunction
