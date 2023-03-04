vim9script

def Request(server: dict<any>, method: string, params: dict<any>, Callback: func): void
    var result = server.request(method, params, Callback)
    if !result
        lsc#message#error('Failed to call ' .. method)
        lsc#message#error('Server status: ' .. lsc#server#status(&filetype))
    endif
enddef

export def ServerForFileType(filetype: string): dict<any>
    if !has_key(g:lsc_servers_by_filetype, filetype) | return {} | endif
    return lsc#server#servers()[g:lsc_servers_by_filetype[filetype]]
enddef

export def LspRequestWithServer(server: dict<any>, method: string, params: dict<any>, Callback: func): void
    Request(server, method, params, Callback)
enddef

export def LspRequest(method: string, params: dict<any>, Callback: func): void
    var server = ServerForFileType(&filetype)
    Request(server, method, params, Callback)
enddef

