vim9script

import autoload "../../lazyload/util.vim"
import autoload "../../lazyload/gates.vim"
import autoload "../../lazyload/highlight.vim"
import autoload "../../lazyload/diagnostics.vim"
import autoload "../../lazyload/cursor.vim"
import autoload "../../lazyload/signature_help.vim"

var g_null_channel: channel

export def NullChannel(): channel
    return g_null_channel
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
                \ 'range': {
                \ 'start': {'line': start_line, 'character': start_char},
                \ 'end': {'line': adj_end_line, 'character': adj_end_char}
                \ },
                \ 'text': text,
                \ 'rangeLength': length
                \ }
    return result
enddef

export def GetDidChangeParam(file_versions: dict<any>, file_path: string, file_content: dict<list<string>>, incremental: bool): dict<any>
    var document_params = {'textDocument': { 'uri': util.OsFilePrefix() .. file_path, 'version': file_versions[file_path]}}
    var current_content = getbufline(bufnr(file_path), 1, '$')
    var params = {}
    if incremental
        var old_content = file_content[file_path]
        var change = ContentsDiff(old_content, current_content)
        # ToDo: remove diff.vim later
        # var change = lsc#diff#compute(old_content, current_content)
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
            \ 1: "Text", 2: "Method", 3: "Function", 4: "Constructor", 5: "Field",
            \ 6: "Variable", 7: "Class", 8: "Interface", 9: "Module", 10: "Property",
            \ 11: "Unit", 12: "Value", 13: "Enum", 14: "Keyword", 15: "Snippet",
            \ 16: "Color", 17: "File", 18: "Reference", 19: "Folder", 20: "EnumMember",
            \ 21: "Constant", 22: "Struct", 23: "Event", 24: "Operator", 25: "TypeParameter"
            \ }
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
    var proj_root = lsc#server#proj_root()
    if len(items) > 0 && !empty(proj_root)
        for idx in range(info.start_idx - 1, info.end_idx - 1)
            var line = ""
            var file_path = fnamemodify(bufname(items[idx].bufnr), ':p:.')
            if file_path[0 : len(proj_root) - 1] ==# proj_root
                file_path = file_path[len(proj_root) + 1 :]
            endif
            line = line .. file_path .. " || " .. items[idx].lnum .. " || " .. trim(items[idx].text)
            add(modified_qflist, line)
        endfor
    endif
    return modified_qflist
enddef

export def OsNormalisePath(path: string): string
    if has('win32')
        return substitute(path, '\\', '/', 'g')
    endif
    return path
enddef

export def NormalisePath(original_path: string): string
    var full_path = original_path
    if full_path !~# '^/\|\%([c-zC-Z]:[/\\]\)'
        full_path = getcwd() .. '/' .. full_path
    endif
    full_path = OsNormalisePath(full_path)
    return full_path
enddef

export def FullAbsPath(): string
    var full_path = expand('%:p')
    if full_path ==# expand('%')
        full_path = NormalisePath(getbufinfo('%')[0].name)
    elseif has('win32')
        full_path = OsNormalisePath(full_path)
    endif
    return full_path
enddef

export def CleanAllMatchs(): void
    highlight.HighlightClear()
    cursor.Clean()
    clearmatches()
enddef

export def CleanAllForFile(filetype: string): void
    diagnostics.DiagCleanForFile(filetype)
    lsc#complete#clean(filetype)
    lsc#file#clean(filetype)
enddef

export def DiagnosticsSetForFile(file_path: string, diags: list<any>): void
    diagnostics.SetForFile(file_path, diags)
enddef

export def GateResult(name: string, Callback: func, vargs: list<any>): func
    return gates.CreateOrGet(name, Callback, vargs)
enddef

export def DiagForLine(file: string, line: number): list<any>
    return cursor.ForLine(diagnostics.ForFile(file).lsp_diagnostics, file, line)
enddef

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
        var vim_item = CompletionItemWord(lsp_item)
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

def Format(method: string, params: dict<any>): dict<any>
    return {'method': method, 'params': params}
enddef

export def Send(ch: channel, method: string, params: dict<any>, Cb: func): void
    ch_sendexpr(ch, Format(method, params), {"callback": (channel, msg) => Cb(msg)})
enddef

export def Publish(ch: channel, method: string, params: dict<any>): void
    call ch_sendexpr(ch, Format(method, params))
enddef

export def Reply(ch: channel, id: number, result: any): void
    ch_sendexpr(ch, {'id': id, 'result': result})
enddef

export def Buffers_reset_state(filetypes: list<any>): void
    lsc#common#CleanAllMatchs()
    for filetype in filetypes
        lsc#common#CleanAllForFile(filetype)
    endfor
enddef

var g_flush_timers = {}
export def FileOnChange(...args: list<string>): void
    var file_path = lsc#common#FullAbsPath()
    var filetype = &filetype
    if len(args) == 1
        file_path = args[0]
        filetype = getbufvar(lsc#file#bufnr(file_path), '&filetype')
    endif
    if has_key(g_flush_timers, file_path)
        timer_stop(g_flush_timers[file_path])
    endif
    g_flush_timers[file_path] = timer_start(get(g:, 'lsc_change_debounce_time', 500),
                \ (_) => File_flush_if_changed(file_path, filetype),
                \ {'repeat': 1})
enddef

def File_flush_if_changed(file_path: string, filetype: string): void
    var file_versions = lsc#file#file_versions()
    if !has_key(g_flush_timers, file_path) | return | endif
    if !has_key(file_versions, file_path) | return | endif

    file_versions[file_path] += 1
    timer_stop(g_flush_timers[file_path])
    unlet g_flush_timers[file_path]

    var server = lsc#server#forFileType(filetype)
    var file_content = lsc#file#file_content()
    var inc_sync = get(g:, 'lsc_enable_incremental_sync', true) && server.capabilities.textDocumentSync.incremental
    var params = lsc#common#GetDidChangeParam(file_versions, file_path, file_content, inc_sync)
    call lsc#common#Publish(server.channel, 'textDocument/didChange', params)
    doautocmd <nomodeline> User LSCOnChangesFlushed
enddef

export def FileFlushChanges(): void
    File_flush_if_changed(lsc#common#FullAbsPath(), &filetype)
enddef

def Handle_publishDiagnostics(server: dict<any>, msg: dict<any>): void
    var file_path = lsc#uri#documentPath(msg["params"]['uri'])
    lsc#common#DiagnosticsSetForFile(file_path, msg["params"]['diagnostics'])
enddef

def Handle_showMessage(server: dict<any>, msg: dict<any>): void
    lsc#message#show(msg["params"]['message'], msg["params"]['type'])
enddef

def Handle_showMessageRequest(server: dict<any>, msg: dict<any>): void
    var response = lsc#message#showRequest(msg["params"]['message'], msg["params"]['actions'])
    lsc#common#Reply(server.channel, msg["id"], response)
enddef

def Handle_logMessage(server: dict<any>, msg: dict<any>): void
    if lsc#config#shouldEcho(server, msg["params"].type)
        lsc#message#log(msg["params"], msg["params"].type)
        echom msg
    endif
enddef

def Handle_progress(server: dict<any>, msg: dict<any>): void
    if has_key(msg["params"], 'message')
        var full = msg["params"]['title'] .. msg["params"]['message']
        lsc#message#show('Progress ' .. full)
    elseif has_key(msg["params"], 'done')
        lsc#message#show('Finished ' .. msg["params"]['title'])
    else
        lsc#message#show('Starting ' .. msg["params"]['title'])
    endif
enddef

def Handle_applyEdit(server: dict<any>, msg: dict<any>): void
    var applied = lsc#edit#apply(msg["params"].edit)
    lsc#common#Reply(server.channel, msg["id"], applied)
enddef

def Handle_configuration(server: dict<any>, msg: dict<any>): void
    var items = msg["params"].items
    var response = map(items, (_, item) => lsc#server#Get_workspace_config(server.config, item))
    lsc#common#Reply(server.channel, msg["id"], response)
enddef

var g_notify_cb_dict = {
    "textDocument/publishDiagnostics": Handle_publishDiagnostics,
    "window/showMessage": Handle_showMessage,
    "window/showMessageRequest": Handle_showMessageRequest,
    "window/logMessage": Handle_logMessage,
    "window/progress": Handle_progress,
    "workspace/applyEdit": Handle_applyEdit,
    "workspace/configuration": Handle_configuration,
}

export def Dispatch(server: dict<any>, msg: dict<any>): void
    var method = msg["method"]
    try
        g_notify_cb_dict[method](server, msg)
    catch  /^Vim\%((\a\+)\)\=:E716:/
        lsc#config#handleNotification(server, method, msg["params"])
    endtry
enddef
