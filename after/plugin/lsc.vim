function! g:LSCServerRegister()
    let cfg = {}
    if exists('g:lsc_server_commands')
      let cfg = g:lsc_server_commands
    endif
    for [s:filetype, s:config] in items(cfg)
        if type(s:config) == type({_ -> _}) || executable(split(s:config)[0])
            call RegisterLanguageServer(s:filetype, s:config)
        endif
    endfor
endfunction

call LSCServerRegister()
