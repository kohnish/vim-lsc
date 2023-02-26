vim9script

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

export def DiagnosticsHighlights(self_arg: dict<any>): list<any>
    if !has_key(self_arg, '_highlights')
        self_arg._highlights = []
        for diagnostic in self_arg.lsp_diagnostics
            add(self_arg._highlights, {
                        \ 'group': SeverityGroup(diagnostic.severity),
                        \ 'severity': diagnostic.severity,
                        \ 'ranges': lsc#convert#rangeToHighlights(diagnostic.range),
                        \ })
        endfor
    endif
    return self_arg._highlights
enddef
