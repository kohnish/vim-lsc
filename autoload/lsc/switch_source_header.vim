vim9script

import "./common.vim"

var g_alternative_last_pos = {}

def SwitchToAlternative(results: any): void
    if type(results) != 1
        call lsc#message#error("Alternative not found")
        return
    endif
    var last_file = ""
    var last_line = 0
    var last_col = 0
    if has_key(g_alternative_last_pos, 'textDocument')
        last_file = g_alternative_last_pos["textDocument"]["uri"]
        last_line = g_alternative_last_pos["position"]["line"]
        last_col = g_alternative_last_pos["position"]["character"]
    endif
    g_alternative_last_pos =  { 'textDocument': {'uri': common.Uri()}, 'position': {'line': line('.'), 'character': col('.')}}
    if !empty(results)
        if &modified
            execute "vsplit " .. results
        else
            execute "edit " .. results
        endif
    endif
    if results == last_file
        cursor(last_line, last_col)
    endif
enddef

export def SwitchSourceHeader(): void
    lsc#file#flushChanges()
    var params = {'uri': common.Uri()}
    lsc#server#userCall('textDocument/switchSourceHeader', params, SwitchToAlternative)
enddef
