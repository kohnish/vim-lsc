vim9script

export def WinDo(command: string): void
    var current_window = winnr()
    execute 'keepjumps noautocmd windo ' .. command
    execute 'keepjumps noautocmd :' .. current_window .. 'wincmd w'
enddef

def QuickFixSeverity(type: string): number
    if type ==# 'E' | return 1
    elseif type ==# 'W' | return 2
    elseif type ==# 'I' | return 3
    elseif type ==# 'H' | return 4
    endif
    return 5
enddef

def QuickFixFilename(item: dict<any>): string
    if has_key(item, 'filename')
        return item.filename
    endif
    return NormalizePath(bufname(item.bufnr))
enddef

export def CompareQuickFixItems(i1: dict<any>, i2: dict<any>): number
    var file_1 = QuickFixFilename(i1)
    var file_2 = QuickFixFilename(i2)
    if file_1 != file_2
        return lsc#file#compare(file_1, file_2)
    endif
    if i1.lnum != i2.lnum | return i1.lnum - i2.lnum | endif
    if i1.col != i2.col | return i1.col - i2.col | endif
    if has_key(i1, 'type') && has_key(i2, 'type') && i1.type != i2.type
        return QuickFixSeverity(i2.type) - QuickFixSeverity(i1.type)
    endif
    return i1.text == i2.text ? 0 : i1.text > i2.text ? 1 : -1
enddef


def EncodeChar(char: string): string
    var charcode = char2nr(char)
    return printf('%%%02x', charcode)
enddef

def OsNormalizePath(path: string): string
    if has('win32')
        return substitute(path, '\\', '/', 'g')
    endif
    return path
enddef

def NormalizePath(original_path: string): string
    var full_path = original_path
    if full_path !~# '^/\|\%([c-zC-Z]:[/\\]\)'
        full_path = getcwd() .. '/' .. full_path
    endif
    full_path = OsNormalizePath(full_path)
    return full_path
enddef

def FullPath(): string
    var full_path = expand('%:p')
    if full_path ==# expand('%')
        full_path = NormalizePath(getbufinfo('%')[0].name)
    elseif has('win32')
        full_path = OsNormalizePath(full_path)
    endif
    return full_path
enddef

def EncodePath(value: string): string
    return substitute(value, '\([^a-zA-Z0-9-_.~/]\)', '\=EncodeChar(submatch(1))', 'g')
enddef

export def OsFilePrefix(): string
    if has('win32')
        return 'file:///'
    else
        return 'file://'
    endif
enddef

export def Uri(): string
    var file_path = FullPath()
    return OsFilePrefix() .. EncodePath(file_path)
enddef

export def DocPos(): dict<any>
    return { 'textDocument': {'uri': Uri()},
                \ 'position': {'line': line('.') - 1, 'character': col('.') - 1}
                \ }
enddef

export def PlainDocPos(): dict<any>
    return { 'textDocument': {'uri': Uri()},
                \ 'position': {'line': line('.'), 'character': col('.')}
                \ }
enddef
