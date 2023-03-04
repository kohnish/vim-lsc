vim9script

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
