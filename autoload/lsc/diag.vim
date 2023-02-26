vim9script

def CompareRanges(d1: dict<any>, d2: dict<any>): number
    if d1.range.start.character != d2.range.start.character
        return d1.range.start.character - d2.range.start.character
    endif
    if d1.range.end.line != d2.range.end.line
        return d1.range.end.line - d2.range.end.line
    endif
    return d1.range.end.character - d2.range.end.character
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
                        \ 'group': SeverityGroup(diagnostic.severity),
                        \ 'severity': diagnostic.severity,
                        \ 'ranges': lsc#convert#rangeToHighlights(diagnostic.range),
                        \ })
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
                        \ 'lnum': diagnostic.range.start.line + 1,
                        \ 'col': diagnostic.range.start.character + 1,
                        \ 'text': DiagnosticMessage(diagnostic),
                        \ 'type': SeverityType(diagnostic.severity)
                        \ }
            extend(item, file_ref)
            add(self._list_items, item)
        endfor
        sort(self._list_items, 'lsc#util#compareQuickFixItems')
    endif
    return self._list_items
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
                        \ 'message': DiagnosticMessage(diagnostic),
                        \ 'range': diagnostic.range,
                        \ 'severity': SeverityLabel(diagnostic.severity),
                        \ }
            call add(line, simple)
        endfor
        for val in values(self._by_line)
            call sort(val, CompareRanges)
        endfor
    endif
    return self._by_line
enddef
