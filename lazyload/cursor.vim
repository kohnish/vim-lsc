vim9script

import autoload "./util.vim"
import autoload "./server.vim"

var g_pending = {}
var g_highlights_request = 0

def CompareRanges(d1: dict<any>, d2: dict<any>): number
    if d1.range.start.character != d2.range.start.character
        return d1.range.start.character - d2.range.start.character
    endif
    if d1.range.end.line != d2.range.end.line
        return d1.range.end.line - d2.range.end.line
    endif
    return d1.range.end.character - d2.range.end.character
enddef

def CompareRange(r1: dict<any>, r2: dict<any>): number
    var line_1 = r1.ranges[0][0]
    var line_2 = r2.ranges[0][0]
    if line_1 != line_2 | return line_1 > line_2 ? 1 : -1 | endif
    var col_1 = r1.ranges[0][1]
    var col_2 = r2.ranges[0][1]
    return col_1 - col_2
enddef

def SeverityLabel(severity: number): string
    if severity == 1 | return 'Error'
    elseif severity == 2 | return 'Warning'
    elseif severity == 3 | return 'Info'
    elseif severity == 4 | return 'Hint'
    else | return ''
    endif
enddef

def SeverityGroup(severity: number): string
    return 'lscDiagnostic' .. SeverityLabel(severity)
enddef

def SeverityType(severity: number): string
    if severity == 1 | return 'E'
    elseif severity == 2 | return 'W'
    elseif severity == 3 | return 'I'
    elseif severity == 4 | return 'H'
    else | return ''
    endif
enddef

export def DiagnosticsHighlights(self: dict<any>): list<any>
    if !has_key(self, '_highlights')
        self._highlights = []
        for diagnostic in self.lsp_diagnostics
            add(self._highlights, {
                'group': SeverityGroup(diagnostic.severity),
                'severity': diagnostic.severity,
                'ranges': lsc#convert#rangeToHighlights(diagnostic.range),
            })
        endfor
    endif
    return self._highlights
enddef

def DiagnosticMessage(diagnostic: dict<any>): string
    var message = diagnostic.message
    if has_key(diagnostic, 'code')
        message = message .. ' [' .. diagnostic.code .. ']'
    endif
    return message
enddef

export def DiagnosticsListItems(self: dict<any>, file_path: string): list<any>
    var file_ref = {}
    if !has_key(self, '_list_items')
        self._list_items = []
        var bufnr = lsc#file#bufnr(file_path)
        if bufnr == -1
            file_ref = {'filename': fnamemodify(file_path, ':.')}
        else
            file_ref = {'bufnr': bufnr}
        endif
        for diagnostic in self.lsp_diagnostics
            var item = {
                'lnum': diagnostic.range.start.line + 1,
                'col': diagnostic.range.start.character + 1,
                'text': DiagnosticMessage(diagnostic),
                'type': SeverityType(diagnostic.severity)
            }
            extend(item, file_ref)
            add(self._list_items, item)
        endfor
        sort(self._list_items, 'lsc#util#compareQuickFixItems')
    endif
    return self._list_items
enddef

export def UnderCursor(file_diagnostics: dict<any>): dict<any>
    var line = line('.')
    if !has_key(file_diagnostics, line)
        if line != line('$') | return {} | endif
        for diagnostic_line in keys(file_diagnostics)
            var diag_line_num = str2nr(diagnostic_line)
            if diag_line_num > line
                return file_diagnostics[diag_line_num][0]
            endif
        endfor
        return {}
    endif
    var diagnostics = file_diagnostics[line]
    var col = col('.')
    var closest_diagnostic = {}
    var closest_distance = -1
    var closest_is_within = false
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
    return closest_diagnostic
enddef

export def ForLine(lsp_diagnostics: list<any>, file: string, line: number): list<any>
    var result = []
    for diagnostic in lsp_diagnostics
        if diagnostic.range.start.line <= line && diagnostic.range.end.line >= line
            add(result, diagnostic)
        endif
    endfor
    return result
enddef

export def IsInReference(references: list<any>): number
    var line = line('.')
    var col = col('.')
    var idx = 0
    for reference in references
        for range in reference.ranges
            if line == range[0] && col >= range[1] && col < range[1] + range[2]
                return idx
            endif
        endfor
        idx += 1
    endfor
    return -1
enddef

# def CanHighlightReferences(): bool
#     for current_server in lsc#server#current()
#         if current_server.capabilities.referenceHighlights
#             return true
#         endif
#     endfor
#     return false
# enddef

def ConvertReference(reference: dict<any>): dict<any>
    return {'ranges': lsc#convert#rangeToHighlights(reference.range)}
enddef

export def HighlightReferences(force_in_highlight: bool): void
    # if exists('g:lsc_reference_highlights') && !g:lsc_reference_highlights
    #     return
    # endif
    # if !CanHighlightReferences() | return | endif
    if !force_in_highlight && exists('w:lsc_references') && IsInReference(w:lsc_references) >= 0
        return
    endif
    # if has_key(g_pending, &filetype) && g_pending[&filetype]
    #     return
    # endif
    # g_highlights_request += 1
    var params = lsc#params#documentPosition()
    var current_server = lsc#server#forFileType(&filetype)
    server.Request(current_server.channel, 'textDocument/documentHighlight', params, funcref(HandleHighlights, [g_highlights_request, getcurpos(), bufnr('%'), &filetype]))
enddef

export def Clean(): void
    g_pending[&filetype] = false
    if exists('w:lsc_reference_matches')
        for current_match in w:lsc_reference_matches
            matchdelete(current_match)
        endfor
        unlet w:lsc_reference_matches
        unlet w:lsc_references
    endif
enddef

# ToDo: Fix it properly
def HandleHighlights(request_number: number, old_pos: list<number>, old_buf_nr: number, request_filetype: string, msg: dict<any>): void
    if !has_key(msg, "result")
        return
    endif
    var highlights = msg["result"]
    # if !has_key(g_pending, request_filetype) || !g_pending[request_filetype]
    #     return
    # endif
    # g_pending[request_filetype] = false
    if bufnr('%') != old_buf_nr
        return
    endif
    if request_number != g_highlights_request
        return
    endif
    Clean()
    if empty(highlights) | return | endif
    map(highlights, (_, reference) => ConvertReference(reference))
    sort(highlights, CompareRange)
    if IsInReference(highlights) == -1
        if old_pos != getcurpos()
            HighlightReferences(true)
        endif
        return
    endif

    w:lsc_references = highlights
    w:lsc_reference_matches = []
    for reference in highlights
        var match = matchaddpos('lscReference', reference.ranges, -5)
        add(w:lsc_reference_matches, match)
    endfor
enddef

export def DiagnosticsByLine(self: dict<any>): dict<any>
    var line = []
    if !has_key(self, '_by_line')
        self._by_line = {}
        for diagnostic in self.lsp_diagnostics
            var start_line = string(diagnostic.range.start.line + 1)
            if !has_key(self._by_line, start_line)
                line = []
                self._by_line[start_line] = line
            else
                line = self._by_line[start_line]
            endif
            var simple = {
                'message': DiagnosticMessage(diagnostic),
                'range': diagnostic.range,
                'severity': SeverityLabel(diagnostic.severity),
            }
            add(line, simple)
        endfor
        for val in values(self._by_line)
            sort(val, CompareRanges)
        endfor
    endif
    return self._by_line
enddef
