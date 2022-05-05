if exists('g:lsc_registered_commands') | finish | endif
let g:lsc_registered_commands = 1

if !exists('g:lsc_server_commands') | finish | endif

for [s:filetype, s:config] in items(g:lsc_server_commands)
    if executable(split(s:config)[0])
        call RegisterLanguageServer(s:filetype, s:config)
    endif
endfor
