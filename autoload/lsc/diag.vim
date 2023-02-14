vim9script

# import "./common.vim"

# function! s:DiagnosticsHighlights() abort dict
#   if !has_key(l:self, '_highlights')
#     let l:self._highlights = []
#     for l:diagnostic in l:self.lsp_diagnostics
#       call add(l:self._highlights, {
#           \ 'group': s:SeverityGroup(l:diagnostic.severity),
#           \ 'severity': l:diagnostic.severity,
#           \ 'ranges': lsc#convert#rangeToHighlights(l:diagnostic.range),
#           \})
#     endfor
#   endif
#   return l:self._highlights
# endfunction
# function! s:DiagnosticsListItems(file_path) abort dict
#   if !has_key(l:self, '_list_items')
#     let l:self._list_items = []
#     let l:bufnr = lsc#file#bufnr(a:file_path)
#     if l:bufnr == -1
#       let l:file_ref = {'filename': fnamemodify(a:file_path, ':.')}
#     else
#       let l:file_ref = {'bufnr': l:bufnr}
#     endif
#     for l:diagnostic in l:self.lsp_diagnostics
#       let l:item = {
#           \ 'lnum': l:diagnostic.range.start.line + 1,
#           \ 'col': l:diagnostic.range.start.character + 1,
#           \ 'text': s:DiagnosticMessage(l:diagnostic),
#           \ 'type': s:SeverityType(l:diagnostic.severity)
#           \}
#       call extend(l:item, l:file_ref)
#       call add(l:self._list_items, l:item)
#     endfor
#     call sort(l:self._list_items, 'lsc#util#compareQuickFixItems')
#   endif
#   return l:self._list_items
# endfunction
# function! s:DiagnosticsByLine() abort dict
#   if !has_key(l:self, '_by_line')
#     let l:self._by_line = {}
#     for l:diagnostic in l:self.lsp_diagnostics
#       let l:start_line = string(l:diagnostic.range.start.line + 1)
#       if !has_key(l:self._by_line, l:start_line)
#         let l:line = []
#         let l:self._by_line[l:start_line] = l:line
#       else
#         let l:line = l:self._by_line[l:start_line]
#       endif
#       let l:simple = {
#           \ 'message': s:DiagnosticMessage(l:diagnostic),
#           \ 'range': l:diagnostic.range,
#           \ 'severity': s:SeverityLabel(l:diagnostic.severity),
#           \}
#       call add(l:line, l:simple)
#     endfor
#     for l:line in values(l:self._by_line)
#       call sort(l:line, function('<SID>CompareRanges'))
#     endfor
#   endif
#   return l:self._by_line
# endfunction

# def Diagnostics(file_path: string, lsp_diagnostics: dict<any>): dict<any>
#   return {
#       'lsp_diagnostics': lsp_diagnostics,
#       'Highlights': funcref(DiagnosticsHighlights),
#       'ListItems': funcref(DiagnosticsListItems, [file_path]),
#       'ByLine': funcref(DiagnosticsByLine),
#       }
# enddef

# def Diag_setForFile(file_diagnostics: dict<any>, file_path: string, diagnostics: dict<any>, ): void
#   if (exists('g:lsc_enable_diagnostics') && !g:lsc_enable_diagnostics) || (empty(diagnostics) && !has_key(file_diagnostics, file_path))
#     return
#   endif
#   var visible_change = v:true
#   if !empty(diagnostics)
#     if has_key(file_diagnostics, file_path) && file_diagnostics[file_path].lsp_diagnostics == diagnostics
#       return
#     endif
#     # if exists('s:highest_used_diagnostic')
#     #   if lsc#file#compare(s:highest_used_diagnostic, file_path) >= 0
#     #     if len(
#     #         \ get(
#     #         \   get(s:file_diagnostics, file_path, {}),
#     #         \   'lsp_diagnostics', []
#     #         \ )
#     #         \) > len(diagnostics)
#     #       unlet s:highest_used_diagnostic
#     #     endif
#     #   else
#     #     let l:visible_change = v:false
#     #   endif
#     # endif
#     file_diagnostics[file_path] = Diagnostics(file_path, diagnostics)
#   # else
#   #   unlet s:file_diagnostics[file_path]
#   #   if exists('s:highest_used_diagnostic')
#   #      if lsc#file#compare(s:highest_used_diagnostic, file_path) >= 0
#   #        unlet s:highest_used_diagnostic
#   #      else
#   #        let l:visible_change = v:false
#   #      endif
#   #   endif
#   endif
#   var bufnr = common.bufnr_for_file(file_path)
#   if bufnr != -1
#     call s:UpdateWindowStates(file_path)
#     call lsc#highlights#updateDisplayed(l:bufnr)
#   endif
#   if l:visible_change
#     if exists('s:quickfix_debounce')
#       call timer_stop(s:quickfix_debounce)
#     endif
#     let s:quickfix_debounce = timer_start(100, funcref('<SID>UpdateQuickFix'))
#   endif
#   if exists('#User#LSCDiagnosticsChange')
#     doautocmd <nomodeline> User LSCDiagnosticsChange
#   endif
#   if(file_path ==# lsc#file#fullPath())
#     call lsc#cursor#showDiagnostic()
#   endif
# enddef

# def Diag_clean(filetype: string) void
#   for buffer in getbufinfo({'bufloaded': v:true})
#     if getbufvar(buffer.bufnr, '&filetype') != filetype
#         continue
#     endif
#     call lsc#diagnostics#setForFile(lsc#file#normalize(l:buffer.name), [])
#   endfor
# enddef

# # If the number grows very large returns instead a String like `'500+'`
# export def Diag_count(file_diags: dict<any>): string
#   var total = 0
#   for diagnostics in values(file_diags)
#     total += len(diagnostics.lsp_diagnostics)
#     if total > 500
#       return string(total) .. '+'
#     endif
#   endfor
#   return string(total)
# enddef

