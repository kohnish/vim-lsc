vim9script

import autoload "../autoload/lsc/common.vim"

def Request(channel: channel, method: string, params: dict<any>, Callback: func): void
    lsc#common#Send(channel, method, params, Callback)
enddef

export def ServerForFileType(filetype: string): dict<any>
    if !has_key(g:lsc_servers_by_filetype, filetype) | return {} | endif
    return lsc#server#servers()[g:lsc_servers_by_filetype[filetype]]
enddef

export def LspRequestWithServer(server: dict<any>, method: string, params: dict<any>, Callback: func): void
    Request(server.channel, method, params, Callback)
enddef

export def LspRequest(method: string, params: dict<any>, Callback: func): void
    var server = ServerForFileType(&filetype)
    Request(server.channel, method, params, Callback)
enddef

