vim9script

import autoload "./util.vim"

var g_quickfix_debounce = -1
var g_highest_used_diagnostic = ""

def IsUsed(highest_used: string, idx: number, to_check: string): bool
    return lsc#file#compare(highest_used, to_check) >= 0
enddef

def FirstX(file_list: list<any>): list<any>
    var result = []
    var search_in = file_list
    while len(result) != 31
        var pivot = search_in[rand() % (len(search_in))]
        var accept = []
        var reject = []
        for file in search_in
            if lsc#file#compare(pivot, file) < 0
                add(reject, file)
            else
                add(accept, file)
            endif
        endfor
        var need = 31 - len(result)
        if len(accept) > need
            search_in = accept
        else
            call extend(result, accept)
            search_in = reject
        endif
    endwhile
    return result
enddef

def AllDiagnostics(): list<any>
    var all_diagnostics = []
    var file_diagnostics = lsc#diagnostics#file_diagnostics()
    # var files = keys(file_diagnostics)
    # if g_highest_used_diagnostic != ""
    #     filter(files, funcref(IsUsed, [g_highest_used_diagnostic]))
    # elseif len(files) > 31
    #     files = FirstX(files)
    # endif
    # sort(files, funcref('lsc#file#compare'))
    # for file_path in files
    #     var diagnostics = file_diagnostics[file_path]
    #     extend(all_diagnostics, diagnostics.ListItems())
    #     if len(all_diagnostics) >= 31
    #         g_highest_used_diagnostic = file_path
    #         break
    #     endif
    # endfor
    return all_diagnostics
enddef

def FindNearest(prev: list<any>, items: list<any>): number
    var idx = 1
    for item in items
        if util.CompareQuickFixItems(item, prev) >= 0
            return idx
        endif
        idx += 1
    endfor
    return idx - 1
enddef

def UpdateQuickFix(timer_arg: any): void
    g_quickfix_debounce = -1
    var current = getqflist({'context': 1, 'idx': 1, 'items': 1})
    var context = get(current, 'context', 0)
    if type(context) != type({}) || !has_key(context, 'client') || context.client !=# 'LSC'
        return
    endif
    # var new_list = {'items': AllDiagnostics()}
    var new_list = {'items': lsc#diagnostics#AllDiagnostics()}
    if len(new_list.items) > 0 &&
                \ current.idx > 0 &&
                \ len(current.items) >= current.idx
        var prev_item = current.items[current.idx - 1]
        new_list.idx = FindNearest(prev_item, new_list.items)
    endif
    setqflist([], 'r', new_list)
enddef

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

def UpdateWindowState(window_id: number, diagnostics: dict<any>): void
    settabwinvar(0, window_id, 'lsc_diagnostics', diagnostics)
    var list_info = getloclist(window_id, {'changedtick': 1})
    var new_list = get(list_info, 'changedtick', 0) == 0
    if new_list
        CreateLocationList(window_id, diagnostics.ListItems())
    else
        UpdateLocationList(window_id, diagnostics.ListItems())
    endif
enddef

def UpdateWindowStates(file_path: string): void
    var diagnostics = lsc#diagnostics#forFile(file_path)
    for window_id in win_findbuf(lsc#file#bufnr(file_path))
        call UpdateWindowState(window_id, diagnostics)
    endfor
enddef

export def SetForFile(file_path: string, diagnostics: list<any>): void
    var file_diagnostics = lsc#diagnostics#file_diagnostics()
    if (exists('g:lsc_enable_diagnostics') && !g:lsc_enable_diagnostics) || (empty(diagnostics) && !has_key(file_diagnostics, file_path))
        return
    endif
    var visible_change = true
    if !empty(diagnostics)
        if has_key(file_diagnostics, file_path) && file_diagnostics[file_path].lsp_diagnostics == diagnostics
            return
        endif
        # if exists('s:highest_used_diagnostic')
        #     if lsc#file#compare(s:highest_used_diagnostic, file_path) >= 0
        #         if len(
        #                     \ get(
        #                     \   get(file_diagnostics, file_path, {}),
        #                     \   'lsp_diagnostics', []
        #                     \ )
        #                     \ ) > len(diagnostics)
        #             unlet s:highest_used_diagnostic
        #         endif
        #     else
        #         var visible_change = false
        #     endif
        # endif
        file_diagnostics[file_path] = lsc#diagnostics#DiagObjCreate(file_path, diagnostics)
    else
        unlet file_diagnostics[file_path]
        # if exists('s:highest_used_diagnostic')
        #     if lsc#file#compare(s:highest_used_diagnostic, file_path) >= 0
        #         unlet s:highest_used_diagnostic
        #     else
        #         var visible_change = false
        #     endif
        # endif
    endif
    var bufnr = lsc#file#bufnr(file_path)
    if bufnr != -1
        UpdateWindowStates(file_path)
        lsc#vim9#HighlightsUpdateDisplayed(bufnr)
    endif
    if visible_change
        if g_quickfix_debounce > -1
            timer_stop(g_quickfix_debounce)
        endif
        g_quickfix_debounce = timer_start(100, UpdateQuickFix)
    endif
    if exists('#User#LSCDiagnosticsChange')
        doautocmd <nomodeline> User LSCDiagnosticsChange
    endif
    if file_path ==# lsc#file#fullPath()
        call lsc#diag#ShowDiagnostic()
    endif
enddef
