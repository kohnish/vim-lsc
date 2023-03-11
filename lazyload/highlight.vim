vim9script

import autoload "./diagnostics.vim"
import autoload "./cursor.vim"

def CreateLocationList(window_id: number, items: list<any>): void
    setloclist(window_id, [], ' ', {
                \ 'title': 'LSC Diagnostics',
                \ 'items': items,
                \ })
    var new_id = getloclist(window_id, {'id': 0}).id
    settabwinvar(0, window_id, 'lsc_location_list_id', new_id)
enddef

def UpdateLocationList(window_id: number, items: list<any>): void
    var list_id = gettabwinvar(0, window_id, 'lsc_location_list_id', -1)
    setloclist(window_id, [], 'r', {
                \ 'id': list_id,
                \ 'items': items,
                \ })
enddef

export def DiagnosticsClear(): void
    if !empty(w:lsc_diagnostics.lsp_diagnostics)
        UpdateLocationList(win_getid(), [])
    endif
    unlet w:lsc_diagnostics
enddef

def UpdateWindowState(window_id: number, diags: dict<any>, file_path: string): void
    settabwinvar(0, window_id, 'lsc_diagnostics', diags)
    var list_info = getloclist(window_id, {'changedtick': 1})
    var new_list = get(list_info, 'changedtick', 0) == 0
    var items = cursor.DiagnosticsListItems(diags, file_path)
    if new_list
        CreateLocationList(window_id, items)
    else
        UpdateLocationList(window_id, items)
    endif
enddef

def UpdateCurrentWindow(): void
    var file_path = lsc#common#FullAbsPath()
    var diags = lsc#diagnostics#forFile(file_path)
    if exists('w:lsc_diagnostics') && w:lsc_diagnostics is diags
        return
    endif
    UpdateWindowState(win_getid(), diags, file_path)
enddef

export def EnsureCurrentWindowState(): void
    w:lsc_window_initialized = v:true
    if !has_key(g:lsc_servers_by_filetype, &filetype)
        if exists('w:lsc_diagnostic_matches')
            HighlightClear()
        endif
        if exists('w:lsc_diagnostics')
            DiagnosticsClear()
        endif
        if exists('w:lsc_reference_matches')
            cursor.Clean()
        endif
        return
    endif
    UpdateCurrentWindow()
    Update()
    diagnostics.CursorOnWinEnter()
enddef

export def OnWinEnter(timer_arg: any): void
    if exists('w:lsc_window_initialized')
        return
    endif
    EnsureCurrentWindowState()
enddef

export def UpdateDisplayed(bufnr: number): void
    for window_id in win_findbuf(bufnr)
        win_execute(window_id, 'LSClientHighlightUpdate')
    endfor
enddef

def MarkCurrentWindowFresh(): void
    w:lsc_highlight_source = w:lsc_diagnostics
enddef

def CurrentWindowIsFresh(): bool
    if !exists('w:lsc_diagnostics') | return true | endif
    if !exists('w:lsc_highlights_source') | return false | endif
    return w:lsc_highlights_source is w:lsc_diagnostics
enddef

export def HighlightClear(): void
    if exists('w:lsc_diagnostic_matches')
        for current_match in w:lsc_diagnostic_matches
            matchdelete(current_match)
        endfor
    endif
    w:lsc_diagnostic_matches = []
    if exists('w:lsc_highlights_source')
        unlet w:lsc_highlights_source
    endif
enddef

export def Update(): void
    if !get(g:, 'lsc_diagnostic_highlights', true) | return | endif
    if CurrentWindowIsFresh() | return | endif
    HighlightClear()
    if &diff | return | endif
    var diag_obj_for_file = lsc#diagnostics#forFile(lsc#common#FullAbsPath())
    var highlights = cursor.DiagnosticsHighlights(diag_obj_for_file)
    for highlight in highlights
        var match = 0
        var priority = -1 * highlight.severity
        var group = highlight.group
        var line = line('$')
        if highlight.ranges[0][0] > line
            match = matchadd(group, '\%' .. line .. 'l$', priority)
        elseif len(highlight.ranges) == 1 && highlight.ranges[0][1] > len(getline(highlight.ranges[0][0]))
            var line_range = '\%' .. highlight.ranges[0][0] .. 'l$'
            match = matchadd(group, line_range, priority)
        else
            match = matchaddpos(group, highlight.ranges, priority)
        endif
        add(w:lsc_diagnostic_matches, match)
    endfor
    MarkCurrentWindowFresh()
enddef
