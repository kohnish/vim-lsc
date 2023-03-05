if !exists('s:initialized')
  let s:log_size = 10
  let s:initialized = v:true
endif

function! lsc#protocol#open(command, on_message, on_err, on_exit) abort
  let l:c = {
      \ '_call_id': 0,
      \ '_in': [],
      \ '_out': [],
      \ '_buffer': [],
      \ '_on_message': lsc#util#async('message handler', a:on_message),
      \ '_callbacks': {},
      \}
  function! l:c.request(method, params, callback, options) abort
    let l:self._call_id += 1
    let l:message = s:Format(a:method, a:params, l:self._call_id)
    let l:self._callbacks[l:self._call_id] = get(a:options, 'sync', v:false)
        \ ? [a:callback]
        \ : [lsc#util#async('request callback for '.a:method, a:callback)]
    call l:self._send(l:message)
  endfunction
  function! l:c.notify(method, params) abort
    let l:message = s:Format(a:method, a:params, v:null)
    call l:self._send(l:message)
  endfunction
  function! l:c.respond(id, result) abort
    call l:self._send({'id': a:id, 'result': a:result})
  endfunction
  function! l:c._send(message) abort
    call lsc#util#shift(l:self._in, s:log_size, a:message)
    call l:self._channel.send(s:Encode(a:message))
  endfunction
  function! l:c._receive(message) abort
    call add(l:self._buffer, a:message)
    if has_key(l:self, '_consume') | return | endif
    if lsc#common#Consume(l:self)
      let l:self._consume = timer_start(0,
          \ function('<SID>HandleTimer', [l:self]))
    endif
  endfunction
  let l:channel = lsc#channel#open(a:command, l:c._receive, a:on_err, a:on_exit)
  if type(l:channel) == type(v:null)
    return v:null
  endif
  let l:c._channel = l:channel
  return l:c
endfunction

function! s:HandleTimer(server, ...) abort
  if lsc#common#Consume(a:server)
    let a:server._consume = timer_start(0,
        \ function('<SID>HandleTimer', [a:server]))
  else
    unlet a:server._consume
  endif
endfunction

function! s:Format(method, params, id) abort
  let l:message = {'method': a:method}
  if type(a:params) != type(v:null) | let l:message['params'] = a:params | endif
  if type(a:id) != type(v:null) | let l:message['id'] = a:id | endif
  return l:message
endfunction

" Prepend the JSON RPC headers and serialize to JSON.
function! s:Encode(message) abort
  let a:message['jsonrpc'] = '2.0'
  let l:encoded = json_encode(a:message)
  let l:length = len(l:encoded)
  return 'Content-Length: '.l:length."\r\n\r\n".l:encoded
endfunction
