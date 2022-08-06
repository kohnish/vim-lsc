vim9script

import "./common.vim"

const INLAYHINT_PROP_NAME = "inlayhint"

def InlayHintExists(bnr: number): bool
    return exists('b:inlayhint_prop_list') && !empty(b:inlayhint_prop_list)
enddef

def InlayHintCb(bnr: number, text_edits: list<dict<any>>): void
    if empty(prop_type_get(INLAYHINT_PROP_NAME))
        prop_type_add(INLAYHINT_PROP_NAME, {highlight: 'VertSplit'})
    endif
    if InlayHintExists(bnr)
        ClearInlayHint(bnr)
    endif
    b:inlayhint_prop_list = []
    var counter = 0
    for result in text_edits
        var col_num = result['position']['character'] + 1
        var line_num = result['position']['line'] + 1
        var badge = ' ' .. result['label']
        prop_add(line_num, col_num, {
            id: counter,
            type: INLAYHINT_PROP_NAME,
            text: badge,
            bufnr: bnr,
        })
        add(b:inlayhint_prop_list, counter)
        counter += 1
    endfor
enddef

export def InlayHint(): void
    var params: dict<any>
    params = {
        'textDocument': { 'uri': common.Uri() },
        'range': {
            'start': {'line': 0, 'character': 0},
            'end': {'line': line('$') - 1, 'character': len(getline(line('$')))}
            }
        }
    lsc#server#userCall('clangd/inlayHints', params, function(InlayHintCb, [bufnr('')]))
enddef

export def ClearInlayHint(bnr: number): void
    if InlayHintExists(bnr)
        for i in b:inlayhint_prop_list
            prop_remove({id: i, type: INLAYHINT_PROP_NAME, bufnr: bnr})
        endfor
        b:inlayhint_prop_list = []
    endif
enddef

export def ToggleInlayHint(): void
    var buf_nr = bufnr('')
    if !InlayHintExists(buf_nr)
        InlayHint()
    else
        ClearInlayHint(buf_nr)
    endif
enddef
