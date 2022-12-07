function! g:LSCServerRegister()
    let cfg = {}
    if exists('g:lsc_server_commands')
      let cfg = g:lsc_server_commands
    else
      if exists('*LSClientServerCommandsFunc')
        let cfg = LSClientServerCommandsFunc()
      endif
    endif
    for [s:filetype, s:config] in items(cfg)
        if executable(split(s:config)[0])
            call RegisterLanguageServer(s:filetype, s:config)
        endif
    endfor
endfunction

call LSCServerRegister()
