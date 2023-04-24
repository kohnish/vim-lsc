vim9script

import autoload "./util.vim"
import autoload "./cursor.vim"
import autoload "./log.vim"
import autoload "./highlight.vim"

var g_file_diagnostics = {}
var g_empty_diagnostics = {'lsp_diagnostics': []}

export def DiagCleanForFile(filetype: string): void
    for buffer in getbufinfo({'bufloaded': v:true})
        if getbufvar(buffer.bufnr, '&filetype') != filetype | continue | endif
        SetForFile(lsc#file#normalize(buffer.name), [])
    endfor
enddef

export def ForFile(file_path: string): dict<any>
    if !has_key(g_file_diagnostics, file_path)
        return g_empty_diagnostics
    endif
    return g_file_diagnostics[file_path]
enddef

def AllDiagnostics(): list<any>
    var all_diagnostics = []
    var file_diagnostics = g_file_diagnostics
    var files = keys(file_diagnostics)
    sort(files, lsc#file#compare)
    for file_path in files
        var diagnostics = file_diagnostics[file_path]
        extend(all_diagnostics, cursor.DiagnosticsListItems(diagnostics, file_path))
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

def UpdateDisplayed(bufnr: number): void
    for window_id in win_findbuf(bufnr)
        win_execute(window_id, 'LSClientHighlightUpdate')
    endfor
enddef

export def SetForFile(file_path: string, diagnostics: list<any>): void
    var file_diagnostics = g_file_diagnostics
    if (exists('g:lsc_enable_diagnostics') && !g:lsc_enable_diagnostics) || (empty(diagnostics) && !has_key(file_diagnostics, file_path))
        return
    endif
    if !empty(diagnostics)
        if has_key(file_diagnostics, file_path) && file_diagnostics[file_path].lsp_diagnostics == diagnostics
            return
        endif
        file_diagnostics[file_path] =  {'lsp_diagnostics': diagnostics}
    else
        unlet file_diagnostics[file_path]
    endif
    var bufnr = lsc#file#bufnr(file_path)
    if bufnr != -1
        UpdateDisplayed(bufnr)
    endif
enddef

export def ShowDiagnostic(): void
    var diag_obj = ForFile(lsc#common#FullAbsPath())
    var diagnostic = cursor.UnderCursor(cursor.DiagnosticsByLine(diag_obj))
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

export def DiagHover(): void
    var diag_obj = ForFile(lsc#common#FullAbsPath())
    var file_diagnostics = cursor.DiagnosticsByLine(diag_obj)
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

var g_ensure_diag_state_timer = -1
def EnsureDiagState(arg: any): void
    highlight.EnsureCurrentWindowState()
    g_ensure_diag_state_timer = -1
enddef

export def CursorOnHold(): void
    # if g_ensure_diag_state_timer != -1
    #     timer_stop(g_ensure_diag_state_timer)
    # endif
    # g_ensure_diag_state_timer = timer_start(1000, EnsureDiagState)
    # EnsureDiagState
    highlight.EnsureCurrentWindowState()
    cursor.HighlightReferences(false)
enddef

export def CursorOnWinEnter(): void
    cursor.HighlightReferences(false)
enddef

export def CursorOnChangesFlushed(): void
    var mode = mode()
    if mode ==# 'n' || mode ==# 'no'
        cursor.HighlightReferences(v:false)
    endif
enddef
