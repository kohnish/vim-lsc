vim9script

import autoload "./server.vim"
import autoload "./util.vim"
import autoload "./log.vim"

var g_alternative_last_pos = {}

export def SwitchToAlternative(results: any): void
    if type(results) != 1
        log.Error("Alternative not found")
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
    g_alternative_last_pos =  { 'textDocument': {'uri': util.Uri()}, 'position': {'line': line('.'), 'character': col('.')}}
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

export def Alternative(): void
    var params = {'uri': util.Uri()}
    server.LspRequest('textDocument/switchSourceHeader', params, SwitchToAlternative)
enddef
