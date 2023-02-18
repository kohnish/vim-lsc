vim9script

# import "./common.vim"

export def Common_bufnr_for_file(full_path: string): number
  var buf_nr = bufnr(full_path)
  # if bufnr == -1 && has_key(s:normalized_paths, a:full_path)
  #   let l:bufnr = bufnr(s:normalized_paths[a:full_path])
  # endif
  return buf_nr
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

def DiagnosticMessage(diagnostic: dict<any>): string
  var message = diagnostic.message
  if has_key(diagnostic, 'code')
    message = message .. ' [' .. diagnostic.code .. ']'
  endif
  return message
enddef

def rangeToHighlights(range: dict<any>): list<any>
  var start = range.start
  var end = range.end
  var ranges = []
  if end.line > start.line
    ranges = [[
        start.line + 1,
        start.character + 1,
        99 ]]
    # Matches render wrong until a `redraw!` if lines are mixed with ranges
    var line_hacks = map(range(start.line + 2, end.line), (_, l) => [l, 0, 99])
    extend(ranges, line_hacks)
    add(ranges, [
        end.line + 1,
        1,
        end.character])
  else
    ranges = [[
        start.line + 1,
        start.character + 1,
        end.character - start.character]]
  endif
  return ranges
enddef

def DiagnosticsHighlights(self: dict<any>): dict<any>
  if !has_key(self, '_highlights')
    self._highlights = []
    for diagnostic in self.lsp_diagnostics
      add(self._highlights, {
           'group': SeverityGroup(diagnostic.severity),
           'severity': diagnostic.severity,
           'ranges': rangeToHighlights(diagnostic.range)
          })
    endfor
  endif
  return self._highlights
enddef

def FileCompare(file_1: string, file_2: string): number
  if file_1 == file_2 | return 0 | endif
  var cwd = '^' .. common.OsNormalizePath(getcwd())
  var file_1_in_cwd = file_1 =~# cwd
  var file_2_in_cwd = file_2 =~# cwd
  if file_1_in_cwd && !file_2_in_cwd | return -1 | endif
  if file_2_in_cwd && !file_1_in_cwd | return 1 | endif
  return file_1 > file_2 ? 1 : -1
enddef

def CompareQuickFixItems(i1: string, i2, string): number
  var file_1 = QuickFixFilename(i1)
  var file_2 = QuickFixFilename(i2)
  if file_1 != file_2
    return FileCompare(file_1, file_2)
  endif
  if i1.lnum != i2.lnum | return i1.lnum - i2.lnum | endif
  if i1.col != i2.col | return i1.col - i2.col | endif
  if has_key(i1, 'type') && has_key(i2, 'type') && i1.type != i2.type
    return QuickFixSeverity(i2.type) - QuickFixSeverity(i1.type)
  endif
  return i1.text == i2.text ? 0 : i1.text > i2.text ? 1 : -1
enddef

def DiagnosticsListItems(self: dict<any>, file_path: string): dict<any>
  if !has_key(self, '_list_items')
    var self._list_items = []
    var bufnr = bufnr(file_path)
    var file_ret = {}
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
    sort(self._list_items, CompareQuickFixItems)
  endif
  return self._list_items
enddef

def DiagnosticsByLine(self: dict<any>): dict<any>
  if !has_key(self, '_by_line')
    var self._by_line = {}
    for diagnostic in self.lsp_diagnostics
      var start_line = string(diagnostic.range.start.line + 1)
      var line = []
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
    for line in values(self._by_line)
      sort(line, CompareRanges)
    endfor
  endif
  return self._by_line
enddef

def Diagnostics(file_path: string, lsp_diagnostics: dict<any>): dict<any>
  return {
      'lsp_diagnostics': lsp_diagnostics,
      'Highlights': funcref(DiagnosticsHighlights),
      'ListItems': funcref(DiagnosticsListItems, [file_path]),
      'ByLine': funcref(DiagnosticsByLine),
      }
enddef

def Diag_setForFile(file_diagnostics: dict<any>, file_path: string, diagnostics: dict<any>, ): void
  if (exists('g:lsc_enable_diagnostics') && !g:lsc_enable_diagnostics) || (empty(diagnostics) && !has_key(file_diagnostics, file_path))
    return
  endif
  var visible_change = true
  if !empty(diagnostics)
    if has_key(file_diagnostics, file_path) && file_diagnostics[file_path].lsp_diagnostics == diagnostics
      return
    endif
    # if exists('s:highest_used_diagnostic')
    #   if lsc#file#compare(s:highest_used_diagnostic, file_path) >= 0
    #     if len(
    #         \ get(
    #         \   get(s:file_diagnostics, file_path, {}),
    #         \   'lsp_diagnostics', []
    #         \ )
    #         \) > len(diagnostics)
    #       unlet s:highest_used_diagnostic
    #     endif
    #   else
    #     let l:visible_change = v:false
    #   endif
    # endif
    file_diagnostics[file_path] = Diagnostics(file_path, diagnostics)
  # else
  #   unlet s:file_diagnostics[file_path]
  #   if exists('s:highest_used_diagnostic')
  #      if lsc#file#compare(s:highest_used_diagnostic, file_path) >= 0
  #        unlet s:highest_used_diagnostic
  #      else
  #        let l:visible_change = v:false
  #      endif
  #   endif
  endif
  var bufnr = Common_bufnr_for_file(file_path)
  if bufnr != -1
    call s:UpdateWindowStates(file_path)
    call lsc#highlights#updateDisplayed(l:bufnr)
  endif
  if l:visible_change
    if exists('s:quickfix_debounce')
      call timer_stop(s:quickfix_debounce)
    endif
    let s:quickfix_debounce = timer_start(100, funcref('<SID>UpdateQuickFix'))
  endif
  if exists('#User#LSCDiagnosticsChange')
    doautocmd <nomodeline> User LSCDiagnosticsChange
  endif
  if(file_path ==# lsc#file#fullPath())
    call lsc#cursor#showDiagnostic()
  endif
enddef

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

