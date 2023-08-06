vim9script

def HandleFoldReply(msg: dict<any>): void
    if !has_key(msg, "result")
        return
    endif
    var end_lnum = 0
    var last_lnum = line('$')
    for foldRange in msg["result"]
        end_lnum = foldRange.endLine + 1
        if end_lnum < foldRange.startLine + 2
            end_lnum = foldRange.startLine + 2
        endif
        exe $':{foldRange.startLine + 2}, {end_lnum}fold'
        :silent! foldopen!
    endfor

    if &foldcolumn == 0
        :setlocal foldcolumn=2
    endif
enddef

export def FoldRange()
    var params = {"textDocument": { "uri": lsc#uri#documentUri()}}
    lsc#server#userCall('textDocument/foldingRange', params, HandleFoldReply)
enddef
