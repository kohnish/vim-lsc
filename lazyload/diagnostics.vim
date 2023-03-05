vim9script

import autoload "./util.vim"
import autoload "./highlight.vim"
import autoload "./log.vim"

def AllDiagnostics(): list<any>
    var all_diagnostics = []
    var file_diagnostics = lsc#diagnostics#file_diagnostics()
    var files = keys(file_diagnostics)
    sort(files, lsc#file#compare)
    for file_path in files
        var diagnostics = file_diagnostics[file_path]
        extend(all_diagnostics, diagnostics.ListItems())
    endfor
    return all_diagnostics
enddef

export def ShowInQuickFix(): void
    var diags = AllDiagnostics()
    if len(diags) > 0
        setqflist([], ' ', {
                    \ 'items': AllDiagnostics(),
                    \ 'title': 'LSC Diagnostics',
                    \ 'context': {'client': 'LSC'},
                    \ 'quickfixtextfunc': 'lsc#common#QflistTrimRoot',
                    \ })
        copen
    else
        log.Error("No diagnostics results")
    endif
enddef

export def SetForFile(file_path: string, diagnostics: list<any>): void
    var file_diagnostics = lsc#diagnostics#file_diagnostics()
    if (exists('g:lsc_enable_diagnostics') && !g:lsc_enable_diagnostics) || (empty(diagnostics) && !has_key(file_diagnostics, file_path))
        return
    endif
    if !empty(diagnostics)
        if has_key(file_diagnostics, file_path) && file_diagnostics[file_path].lsp_diagnostics == diagnostics
            return
        endif
        file_diagnostics[file_path] = lsc#diagnostics#DiagObjCreate(file_path, diagnostics)
    else
        unlet file_diagnostics[file_path]
    endif
    var bufnr = lsc#file#bufnr(file_path)
    if bufnr != -1
        highlight.UpdateDisplayed(bufnr)
    endif
enddef
