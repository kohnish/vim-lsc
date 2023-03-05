vim9script

export def UpdateDisplayed(bufnr: number): void
    for window_id in win_findbuf(bufnr)
        win_execute(window_id, 'call lsc#vim9#HighlightsUpdate()')
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

export def Clear(): void
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
    # if !get(g:, 'lsc_diagnostic_highlights', true) | return | endif
    # if CurrentWindowIsFresh() | return | endif
    Clear()
    if &diff | return | endif
    var diag_obj_for_file = lsc#diagnostics#forFile(lsc#file#fullPath())
    for highlight in diag_obj_for_file.Highlights()
        var match = 0
        var priority = -1 * highlight.severity
        var group = highlight.group
        var line = line('$')
        if highlight.ranges[0][0] > line
            match = matchadd(group, '\%' .. line .. 'l$', priority)
        elseif len(highlight.ranges) == 1 && highlight.ranges[0][1] > len(getline(highlight.ranges[0][0]))
            var line_range = '\%' .. highlight.ranges[0][0] .. ' l$'
            match = matchadd(group, line_range, priority)
        else
            match = matchaddpos(group, highlight.ranges, priority)
        endif
        add(w:lsc_diagnostic_matches, match)
    endfor
    # MarkCurrentWindowFresh()
enddef
