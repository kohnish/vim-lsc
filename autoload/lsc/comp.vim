vim9script

def GuessCompletionStart(): number
    var search = col('.') - 2
    var line = getline('.')
    while search > 0
        var char = line[search]
        if char !~# '\w'
            return search + 2
        endif
        search -= 1
    endwhile
    return 1
enddef

export def FindStart(completion_items: list<any>): number
    for item in completion_items
        if has_key(item, 'textEdit')
                    \ && type(item.textEdit) == type({})
            return item.textEdit.range.start.character + 1
        endif
    endfor
    return GuessCompletionStart()
enddef

def CompletionItemWord(lsp_item: dict<any>): dict<any>
    var item = {'abbr': lsp_item.label, 'icase': 1, 'dup': 1}
    if has_key(lsp_item, 'textEdit')
                \ && type(lsp_item.textEdit) == type({})
                \ && has_key(lsp_item.textEdit, 'newText')
        item.word = lsp_item.textEdit.newText
    elseif has_key(lsp_item, 'insertText')
                \ && !empty(lsp_item.insertText)
        item.word = lsp_item.insertText
    else
        item.word = lsp_item.label
    endif
    if has_key(lsp_item, 'insertTextFormat') && lsp_item.insertTextFormat == 2
        item.user_data = json_encode({
                    \ 'snippet': item.word,
                    \ 'snippet_trigger': item.word
                    \ })
        item.word = lsp_item.label
    endif
    return item
enddef


export def CompletionItems(base: string, lsp_items: list<any>): list<any>
    var prefix_case_matches = []
    var prefix_matches = []
    var substring_matches = []

    var prefix_base = '^' .. base

    for lsp_item in lsp_items
        var vim_item = s:CompletionItemWord(lsp_item)
        if vim_item.word =~# prefix_base
            add(prefix_case_matches, vim_item)
        elseif vim_item.word =~? prefix_base
            add(prefix_matches, vim_item)
        elseif vim_item.word =~? base
            add(substring_matches, vim_item)
        else
            continue
        endif
        lsc#common#FinishItem(lsp_item, vim_item)
    endfor

    return prefix_case_matches + prefix_matches + substring_matches
enddef


