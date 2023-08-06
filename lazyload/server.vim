vim9script

export def Request(channel: channel, method: string, params: dict<any>, Callback: func): void
    lsc#common#Send(channel, method, params, Callback)
enddef

export def ServerForFileType(filetype: string): dict<any>
    return lsc#server#forFileType(filetype)
enddef

export def UserRequest(method: string, params: dict<any>, Callback: func): void
    var server = ServerForFileType(&filetype)
    if ch_status(server.channel) == "open"
        Request(server.channel, method, params, Callback)
    else
        lsc#message#log("Language server is not running", 3)
    endif
enddef

