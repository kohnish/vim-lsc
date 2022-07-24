vim9script

def EncodeChar(char: string): string
    var charcode = char2nr(char)
    return printf('%%%02x', charcode)
enddef

def EncodePath(value: string): string
    return substitute(value, '\([^a-zA-Z0-9-_.~/]\)', '\=EncodeChar(submatch(1))', 'g')
enddef

def OsFilePrefix(): string
    if has('win32')
        return 'file:///'
    else
        return 'file://'
    endif
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

export def Uri(): string
    var file_path = FullPath()
    return OsFilePrefix() .. EncodePath(file_path)
enddef

export def DocPos(): dict<any>
    return { 'textDocument': {'uri': Uri()}, 'position': {'line': line('.'), 'character': col('.')}}
enddef

export def IsCompletable(): bool
    var pos = col(".")
    var line = getline(".")
    var surr_chars = ""
    if len(line) > 2
        surr_chars =  line[pos - 4 : pos - 2]
    endif
    if len(trim(surr_chars)) > 2
       var banned_chars = [';', '{', '}', ',', '(', ')', '+']
       if surr_chars[2] == ':' && surr_chars[1] != ':'
           return false
       endif
       for i in banned_chars
           if surr_chars[0] == i || surr_chars[1] == i || surr_chars[2] == i
               return false
           endif
       endfor
       return true
    endif
    return false
enddef

def NumLastDiff(old: list<any>, new: list<any>, offset: number): number
    var length_old = len(old)
    var length_new = len(new)
    var length = length_old
    if length_old > length_new
        length = length_new
    endif
    for i in range(length - 1)
        if old[length_old - i + offset] != new[length_new - i + offset]
            return -1 * i
        endif
    endfor
    return -1 * length
enddef

def NumFirstDiff(old: list<any>, new: list<any>, offset: number): number
    var length_old = len(old)
    var length_new = len(new)
    var length = length_old
    if length_old > length_new
        length = length_new
    endif
    for i in range(length - 1)
        if old[i + offset] != new[i + offset]
            return i
        endif
    endfor
    return length - 1
enddef

def FirstDifference(old: list<any>, new: list<any>): list<any>
    var line_count = min([len(old), len(new)])
    if line_count == 0 | return [0, 0] | endif
    var i = NumFirstDiff(old, new, 0)

    if i >= line_count
      return [line_count - 1, strchars(old[line_count - 1])]
    endif

    var old_line = old[i]
    var new_line = new[i]
    var length = min([strchars(old_line), strchars(new_line)])
    var j = 0
    while j < length
        if strgetchar(old_line, j) != strgetchar(new_line, j)
            break
        endif
        j += 1
    endwhile
    return [i, j]
enddef

def LastDifference(old: list<any>, new: list<any>, start_char: number): list<any>
    var line_count = min([len(old), len(new)])
    if line_count == 0 | return [0, 0] | endif
    var i = NumLastDiff(old, new, -1)
    var old_line = ""
    var new_line = ""
    if i <= -1 * line_count
        i = -1 * line_count
        old_line = strcharpart(old[i], start_char)
        new_line = strcharpart(new[i], start_char)
    else
        old_line = old[i]
        new_line = new[i]
    endif
    var old_line_length = strchars(old_line)
    var new_line_length = strchars(new_line)
    var length = min([old_line_length, new_line_length])
    var j = -1
    while j >= -1 * length
        if strgetchar(old_line, old_line_length + j) != strgetchar(new_line, new_line_length + j)
            break
        endif
        j -= 1
    endwhile
    return [i, j]
enddef

def ExtractText(lines: list<any>, start_line: number, start_char: number, end_line: number, end_char: number): string
    if start_line == len(lines) + end_line
        if end_line == 0 | return '' | endif
        var line = lines[start_line]
        var length = strchars(line) + end_char - start_char + 1
        return strcharpart(line, start_char, length)
    endif

    var result = strcharpart(lines[start_line], start_char) .. "\n"
    for line in lines[start_line + 1 : end_line - 1]
        result = result .. line .. "\n"
    endfor
    if end_line != 0
        var line = lines[end_line]
        var length = strchars(line) + end_char + 1
        result = result .. strcharpart(line, 0, length)
    endif
    return result
enddef

def Length(lines: list<any>, start_line: number, start_char: number, end_line: number, end_char: number): number
    var adj_end_line = len(lines) + end_line
    var adj_end_char = 0
    if adj_end_line >= len(lines)
        adj_end_char = end_char - 1
    else
        adj_end_char = strchars(lines[adj_end_line]) + end_char
    endif
    if start_line == adj_end_line
        return adj_end_char - start_char + 1
    endif

    var result = strchars(lines[start_line]) - start_char + 1
    for line in range(start_line + 1, adj_end_line - 1)
        result += strchars(lines[line]) + 1
    endfor
    result += adj_end_char + 1
    return result
enddef

def ContentsDiff(old: list<any>, new: list<any>): dict<any>
    var first_diff = FirstDifference(old, new)
    var start_line = first_diff[0]
    var start_char = first_diff[1]
    var end_diff = LastDifference(old[start_line : ], new[start_line : ], start_char)
    var end_line = end_diff[0]
    var end_char = end_diff[1]

    var text = ExtractText(new, start_line, start_char, end_line, end_char)
    var length = Length(old, start_line, start_char, end_line, end_char)

    var adj_end_line = len(old) + end_line
    var adj_end_char = end_line == 0 ? 0 : strchars(old[end_line]) + end_char + 1

    var result = {
        'range': {
            'start': {'line': start_line, 'character': start_char},
            'end': {'line': adj_end_line, 'character': adj_end_char}
            },
        'text': text,
        'rangeLength': length
        }
  return result
enddef

export def GetDidChangeParam(file_versions: dict<any>, file_path: string, file_content: dict<list<string>>, incremental: bool): dict<any>
    var document_params = {'textDocument': { 'uri': OsFilePrefix() .. file_path, 'version': file_versions[file_path]}}
    var current_content = getbufline(bufnr(file_path), 1, '$')
    var params = {}
    if incremental
        var old_content = file_content[file_path]
        var change = ContentsDiff(old_content, current_content)
        file_content[file_path] = current_content
        var incremental_params = copy(document_params)
        incremental_params.contentChanges = [change]
        params = incremental_params
    else
        var full_params = copy(document_params)
        var change = {'text': join(current_content, "\n") .. "\n"}
        full_params.contentChanges = [change]
        params = full_params
    endif
    return params
enddef

# Fill out the non-word fields of the vim completion item from an LSP item.
#
# Deprecated suggestions get a strike-through on their `abbr`.
# The `kind` field is translated from LSP numeric values into a single letter
# vim kind identifier.
# The `menu` and `info` vim fields are normalized from the `detail` and
# `documentation` LSP fields.
def CompletionItemKind(lsp_kind: number): string
    if lsp_kind == 1
        return 'Text'
    elseif lsp_kind == 2
        return 'Method'
    elseif lsp_kind == 3
        return 'Function'
    elseif lsp_kind == 4
        return 'Constructor'
    elseif lsp_kind == 5
        return 'Field'
    elseif lsp_kind == 6
        return 'Variable'
    elseif lsp_kind == 7
        return 'Class'
    elseif lsp_kind == 8
        return 'Interface'
    elseif lsp_kind == 9
        return 'Module'
    elseif lsp_kind == 10
        return 'Property'
    elseif lsp_kind == 11
        return 'Unit'
    elseif lsp_kind == 12
        return 'Value'
    elseif lsp_kind == 13
        return 'Enum'
    elseif lsp_kind == 14
        return 'Keyword'
    elseif lsp_kind == 15
        return 'Snippet'
    elseif lsp_kind == 16
        return 'Color'
    elseif lsp_kind == 17
        return 'File'
    elseif lsp_kind == 18
        return 'Reference'
    elseif lsp_kind == 19
        return 'Folder'
    elseif lsp_kind == 20
        return 'EnumMember'
    elseif lsp_kind == 21
        return 'Constant'
    elseif lsp_kind == 22
        return 'Struct'
    elseif lsp_kind == 23
        return 'Event'
    elseif lsp_kind == 24
        return 'Operator'
    elseif lsp_kind == 25
        return 'TypeParameter'
    else
        return ''
    endif
enddef

export def FinishItem(lsp_item: dict<any>, vim_item: dict<any>): void
    if get(lsp_item, 'deprecated', v:false) || index(get(lsp_item, 'tags', []), 1) >= 0
        vim_item.abbr = substitute(vim_item.word, '.', "\\0\<char-0x0336>", 'g')
    endif
    if has_key(lsp_item, 'kind')
        vim_item.kind = CompletionItemKind(lsp_item.kind)
    endif
    if has_key(lsp_item, 'detail') && lsp_item.detail != v:null
        var detail_lines = split(lsp_item.detail, "\n")
        if len(detail_lines) > 0
            vim_item.menu = detail_lines[0]
            vim_item.info = lsp_item.detail
        endif
    endif
    if has_key(lsp_item, 'documentation')
        var documentation = lsp_item.documentation
        if has_key(vim_item, 'info')
            vim_item.info = vim_item.info .. "\n\n"
        else
            vim_item.info = ''
        endif
        if type(documentation) == type('')
            vim_item.info = vim_item.info .. documentation
        elseif type(documentation) == type({}) && has_key(documentation, 'value')
            vim_item.info = vim_item.info .. documentation.value
        endif
    endif
enddef

export def FocusIfOpen(filename: string): void
    for buf in getbufinfo()
        if buf.loaded && buf.name == filename && len(buf.windows) > 0
            keepjumps win_gotoid(buf.windows[0])
            return
        endif
    endfor
enddef

export def QflistTrimRoot(info: dict<any>): list<any>
    var items = getqflist()
    var modified_qflist = []
    if (len(items) > 0 && exists('g:lsc_proj_dir'))
        for idx in range(info.start_idx - 1, info.end_idx - 1)
            var line = ""
            var file_path = fnamemodify(bufname(items[idx].bufnr), ':p:.')
            if file_path[0 : len(g:lsc_proj_dir) - 1] ==# g:lsc_proj_dir
                file_path = file_path[len(g:lsc_proj_dir) + 1 :]
            endif
            line = line .. file_path .. " || " .. items[idx].lnum .. " || " .. trim(items[idx].text)
            add(modified_qflist, line)
        endfor
    endif
    return modified_qflist
enddef

export def DiagHover(): void
    var file_diagnostics = lsc#diagnostics#forFile(lsc#file#fullPath()).ByLine()
    var line = line('.')
    var diag_msg = {}

    if !has_key(file_diagnostics, line)
        if line != line('$') | return | endif
        for diagnostic_line in keys(file_diagnostics)
            if len(diagnostic_line) > line
                diag_msg = file_diagnostics[diagnostic_line][0]
            endif
        endfor
        return
    endif

    var diagnostics = file_diagnostics[line]
    var col = col('.')
    var closest_diagnostic = {}
    var closest_distance = -1
    var closest_is_within = v:false
    for diagnostic in file_diagnostics[line]
        var range = diagnostic.range
        var is_within = range.start.character < col && (range.end.line >= line || range.end.character > col)
        if closest_is_within && !is_within
            continue
        endif
        var distance = abs(range.start.character - col)
        if closest_distance < 0 || distance < closest_distance
            closest_diagnostic = diagnostic
            closest_distance = distance
            closest_is_within = is_within
        endif
    endfor
    if len(closest_distance) > 0
        diag_msg = closest_diagnostic
    endif
    if has_key(diag_msg, "message")
        var diag_popup_arr = split(diag_msg["message"], "\n")
        var i = 0
        for d in diag_popup_arr
            diag_popup_arr[i] = " " .. diag_popup_arr[i] .. " "
            i = i + 1
        endfor
        insert(diag_popup_arr, '')
        add(diag_popup_arr, '')
        popup_atcursor(diag_popup_arr, {})
    endif
enddef

def IncomingCallQfResultCb(location: dict<any>): dict<any>
    var start = location.from["selectionRange"]["start"]
    var item = {'lnum': start["line"] + 1, 'col': start["character"] + 1}
    var file_path = lsc#uri#documentPath(location["from"].uri)
    item.filename = fnamemodify(file_path, ':.')
    item.text = location["from"].name
    return item
enddef

def ShowIncomingCallQf(results: list<any>): void
    if len(results) > 0
         map(results, (_, ref) => IncomingCallQfResultCb(ref))
         sort(results, lsc#util#compareQuickFixItems)
         setqflist([], ' ', {'title': 'Incoming calls', 'items': results, 'quickfixtextfunc': QflistTrimRoot})
        copen
    endif
enddef

def IncomingCallReq(results: list<any>): void
    if len(results) > 0
        var params = {"item": results[0]}
        lsc#server#userCall('callHierarchy/incomingCalls', params, ShowIncomingCallQf)
    endif
enddef

export def IncomingCalls(): void
    lsc#file#flushChanges()
    var params = lsc#params#documentPosition()
    lsc#server#userCall('textDocument/prepareCallHierarchy', params, IncomingCallReq)
enddef
