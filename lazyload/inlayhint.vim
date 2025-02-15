vim9script

import autoload "./server.vim"
import autoload "./util.vim"
import autoload "./log.vim"

const INLAYHINT_PROP_NAME = "inlayhint"
prop_type_add(INLAYHINT_PROP_NAME, {highlight: 'VertSplit'})

def InlayHintExists(bnr: number): bool
    return exists('b:inlayhint_prop_list') && !empty(b:inlayhint_prop_list)
enddef

def InlayHintCb(bnr: number, msg: dict<any>): void
    if !has_key(msg, "result")
        log.Error("No inlay hints found")
        return
    endif
    var text_edits = msg["result"]
    b:inlayhint_waiting = false
    if b:inlayhint_cancel
        b:inlayhint_cancel = false
        ClearInlayHint(bnr)
        return
    endif
    if InlayHintExists(bnr)
        ClearInlayHint(bnr)
    endif
    b:inlayhint_prop_list = []
    for result in text_edits
        var col_num = result['position']['character'] + 1
        var line_num = result['position']['line'] + 1
        var badge = ' ' .. result['label']
        var id = prop_add(line_num, col_num, {
            type: INLAYHINT_PROP_NAME,
            text: badge,
            bufnr: bnr,
        })
        add(b:inlayhint_prop_list, id)
    endfor
enddef

export def InlayHintReq(): void
    if exists("b:inlayhint_waiting")
        if b:inlayhint_waiting
            return
        endif
    else
        b:inlayhint_waiting = false
    endif
    if !exists("b:inlayhint_cancel")
        b:inlayhint_cancel = false
    endif
    var params: dict<any>
    params = {
        'textDocument': { 'uri': util.Uri() },
        'range': {
            'start': {'line': 0, 'character': 0},
            'end': {'line': line('$') - 1, 'character': len(getline(line('$')))}
        }
    }
    b:inlayhint_waiting = true
    server.UserRequest('clangd/inlayHints', params, function(InlayHintCb, [bufnr('')]))
enddef

export def ClearInlayHint(bnr: number): void
    if exists("b:inlayhint_waiting")
        if b:inlayhint_waiting
            b:inlayhint_cancel = true
            return
        endif
    else
        b:inlayhint_waiting = false
    endif
    if !exists("b:inlayhint_cancel")
        b:inlayhint_cancel = false
    endif
    if InlayHintExists(bnr)
        for i in b:inlayhint_prop_list
            prop_remove({id: i, type: INLAYHINT_PROP_NAME, bufnr: bnr})
        endfor
        b:inlayhint_prop_list = []
    endif
enddef

export def InlayHint(): void
    var buf_nr = bufnr('')
    if !InlayHintExists(buf_nr)
        InlayHintReq()
    else
        ClearInlayHint(buf_nr)
    endif
enddef
