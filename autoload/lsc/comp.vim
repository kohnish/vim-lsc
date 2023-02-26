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

