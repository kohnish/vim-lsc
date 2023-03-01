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
const g_lsp_dict = {
    1: "Text", 2: "Method", 3: "Function", 4: "Constructor", 5: "Field",
    6: "Variable", 7: "Class", 8: "Interface", 9: "Module", 10: "Property",
    11: "Unit", 12: "Value", 13: "Enum", 14: "Keyword", 15: "Snippet",
    16: "Color", 17: "File", 18: "Reference", 19: "Folder", 20: "EnumMember",
    21: "Constant", 22: "Struct", 23: "Event", 24: "Operator", 25: "TypeParameter"
}
def CompletionItemKind(lsp_kind: number): string
    try
        return g_lsp_dict[lsp_kind]
    catch
    endtry
    return ''
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

export def GetLineByteFromPos(bnr: number, pos: dict<number>): number
    var col: number = pos.character
    # When on the first character, we can ignore the difference between byte and
    # character
    if col > 0
        # Need a loaded buffer to read the line and compute the offset
        if !bnr->bufloaded()
            bnr->bufload()
        endif

        var ltext: list<string> = bnr->getbufline(pos.line + 1)
        if !ltext->empty()
            var bidx = ltext[0]->byteidx(col)
            if bidx != -1
                return bidx
            endif
        endif
    endif
    return col
enddef

def Set_lines(lines: list<string>, A: list<number>, B: list<number>, new_lines: list<string>): list<string>
    var i_0: number = A[0]

    # If it extends past the end, truncate it to the end. This is because the
    # way the LSP describes the range including the last newline is by
    # specifying a line number after what we would call the last line.
    var numlines: number = lines->len()
    var i_n = [B[0], numlines - 1]->min()

    if i_0 < 0 || i_0 >= numlines || i_n < 0 || i_n >= numlines
        var msg = "set_lines: Invalid range, A = " .. A->string()
        msg ..= ", B = " ..    B->string() .. ", numlines = " .. numlines
        msg ..= ", new lines = " .. new_lines->string()
        return lines
    endif

    # save the prefix and suffix text before doing the replacements
    var prefix: string = ''
    var suffix: string = lines[i_n][B[1] :]
    if A[1] > 0
        prefix = lines[i_0][0 : A[1] - 1]
    endif

    var new_lines_len: number = new_lines->len()

    var n: number = i_n - i_0 + 1
    if n != new_lines_len
        if n > new_lines_len
            # remove the deleted lines
            lines->remove(i_0, i_0 + n - new_lines_len - 1)
        else
            # add empty lines for newly the added lines (will be replaced with the
            # actual lines below)
            lines->extend(repeat([''], new_lines_len - n), i_0)
        endif
    endif

    # replace the previous lines with the new lines
    for i in range(new_lines_len)
        lines[i_0 + i] = new_lines[i]
    endfor

    # append the suffix (if any) to the last line
    if suffix != ''
        var i = i_0 + new_lines_len - 1
        lines[i] = lines[i] .. suffix
    endif

    # prepend the prefix (if any) to the first line
    if prefix != ''
        lines[i_0] = prefix .. lines[i_0]
    endif

    return lines
enddef

def Edit_sort_func(a: dict<any>, b: dict<any>): number
    if a.A[0] != b.A[0]
        return b.A[0] - a.A[0]
    endif
    if a.A[1] != b.A[1]
        return b.A[1] - a.A[1]
    endif
    return 0
enddef

var g_format_delay = false
def FormatCb(bnr: number, text_edits: list<dict<any>>): void
    if text_edits->empty()
        return
    endif

    var orig_cursor_pos = getcurpos()
    # if the buffer is not loaded, load it and make it a listed buffer
    if !bnr->bufloaded()
        bnr->bufload()
    endif
    setbufvar(bnr, '&buflisted', true)

    var start_line: number = 4294967295
    var finish_line: number = -1
    var updated_edits: list<dict<any>> = []
    var start_row: number
    var start_col: number
    var end_row: number
    var end_col: number

    # create a list of buffer positions where the edits have to be applied.
    for e in text_edits
        # Adjust the start and end columns for multibyte characters
        start_row = e.range.start.line
        start_col = GetLineByteFromPos(bnr, e.range.start)
        end_row = e.range.end.line
        end_col = GetLineByteFromPos(bnr, e.range.end)
        start_line = [e.range.start.line, start_line]->min()
        finish_line = [e.range.end.line, finish_line]->max()
        updated_edits->add({A: [start_row, start_col], B: [end_row, end_col], lines: e.newText->split("\n", true)})
    endfor

    # Reverse sort the edit operations by descending line and column numbers so
    # that they can be applied without interfering with each other.
    updated_edits->sort(Edit_sort_func)

    var lines: list<string> = bnr->getbufline(start_line + 1, finish_line + 1)
    # This causes issues with haskell-language-server sometimes so just add lines without checking eol stuff
    # var fix_eol: bool = bnr->getbufvar('&fixeol')
    # var set_eol = fix_eol && bnr->getbufinfo()[0].linecount <= finish_line + 1
    # if set_eol && lines[-1]->len() != 0
    #     lines->add('')
    # endif
    if bnr->getbufinfo()[0].linecount <= finish_line + 1
        lines->add('')
    endif

    for e in updated_edits
        var A: list<number> = [e.A[0] - start_line, e.A[1]]
        var B: list<number> = [e.B[0] - start_line, e.B[1]]
        lines = Set_lines(lines, A, B, e.lines)
    endfor

    # If the last line is empty and we need to set EOL, then remove it.
    # if set_eol && lines[-1]->len() == 0
    #     lines->remove(-1)
    # endif

    # Delete all the lines that need to be modified
    bnr->deletebufline(start_line + 1, finish_line + 1)

    # if the buffer is empty, appending lines before the first line adds an
    # extra empty line at the end. Delete the empty line after appending the
    # lines.
    var dellastline: bool = false
    if start_line == 0 && bnr->getbufinfo()[0].linecount == 1 && bnr->getbufline(1)[0] == ''
        dellastline = true
    endif

    # Append the updated lines
    appendbufline(bnr, start_line, lines)

    # This causes issues with haskell-language-server
    # if dellastline
    # bnr->deletebufline(bnr->getbufinfo()[0].linecount)
    # endif
    setpos('.', orig_cursor_pos)
enddef

def Format_(arg: any): void
    g_format_delay = true
    lsc#file#flushChanges()
    var params: dict<any>
    params = { 'textDocument': { 'uri': Uri() } }
    if exists('g:lsc_format_options')
        params['options'] = g:lsc_format_options
    endif
    lsc#server#userCall('textDocument/formatting', params, function(FormatCb, [bufnr('')]))
enddef

export def Format(): void
    if g_format_delay
        g_format_delay = false
        timer_start(1000, Format_)
    else
        Format_(0)
    endif
enddef
