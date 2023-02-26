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
        var is_within = range.start.character < col &&
                    \ (range.end.line >= line || range.end.character > col)
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

def ForLine(lsp_diagnostics: dict<any>, file: string, line: number): list<any>
    var result = []
    for diagnostic in lsp_diagnostics
        if diagnostic.range.start.line <= a:line &&
                    \ diagnostic.range.end.line >= a:line
            add(result, diagnostic)
        endif
    endfor
    return result
enddef

export def ShowDiagnostic(): void
    if !get(g:, 'lsc_diagnostic_highlights', true) | return | endif
    var diagnostic = lsc#diagnostics#underCursor()
    if has_key(diagnostic, 'message')
        var max_width = &columns - 1 
        var has_ruler = &ruler &&
                    \ (&laststatus == 0 || (&laststatus == 1 && winnr('$') < 2))
        if has_ruler | max_width -= 18 | endif
        if &showcmd | max_width -= 11 | endif
        var message = strtrans(diagnostic.message)
        if strdisplaywidth(message) > max_width
            max_width -= 1
            var truncated = strcharpart(message, 0, max_width)
            while strdisplaywidth(truncated) > max_width
                truncated = strcharpart(truncated, 0, strchars(truncated) - 1)
            endwhile
            echo truncated .. "\u2026"
        else
            echo message
        endif
    else
        echo ''
    endif
enddef

export def IsInReference(references: list<any>): number
  var line = line('.')
  var col = col('.')
  var idx = 0
  for reference in references
    for range in reference.ranges
      if line == range[0]
          \ && col >= range[1]
          \ && col < range[1] + range[2]
        return idx
      endif
    endfor
    idx += 1
  endfor
  return -1
enddef
