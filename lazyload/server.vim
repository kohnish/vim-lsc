vim9script

export def LspRequest(method: string, params: dict<any>, Callback: func): void
    var server = lsc#server#forFileType(&filetype)[0]
    var result = server.request(method, params, Callback)
    if !result
        lsc#message#error('Failed to call ' .. method)
        lsc#message#error('Server status: ' .. lsc#server#status(&filetype))
    endif
enddef
