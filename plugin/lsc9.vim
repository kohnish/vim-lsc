vim9script

import autoload "../lazyload/hierarchy.vim"
import autoload "../lazyload/diagnostics.vim"
import autoload "../lazyload/switch_source_header.vim"
import autoload "../lazyload/inlayhint.vim"
import autoload "../lazyload/signature_help.vim"
import autoload "../lazyload/format.vim"
import autoload "../lazyload/highlight.vim"
import autoload "../lazyload/util.vim"
import autoload "../lazyload/cursor.vim"

command! LSClientDiagnosticHover diagnostics.DiagHover()
command! LSClientIncomingCalls hierarchy.CallHierarchy("incoming")
command! LSClientOutgoingCalls hierarchy.CallHierarchy("outgoing")
command! LSClientSwitchSourceHeader switch_source_header.Alternative()
command! LSClientAllDiagnostics diagnostics.ShowInQuickFix()
command! LSClientSignatureHelp signature_help.SignatureHelp()
command! LSClientFormat format.Format()
command! LSClientInlayHintToggle inlayhint.InlayHint()
command! LSClientEnsureCurrentWindowState highlight.EnsureCurrentWindowState()
command! LSClientHighlightUpdate highlight.Update()
# command! LSClientWindowDiagnostics call lsc#diagnostics#showLocationList()
# command! LSClientLineDiagnostics call lsc#diagnostics#echoForLine()

def IfEnabled(Cb: func): void
    if !has_key(g:lsc_servers_by_filetype, &filetype) | return | endif
    if !&modifiable | return | endif
    if !lsc#server#filetypeActive(&filetype) | return | endif
    Cb()
enddef

augroup LSC9
    autocmd!
    autocmd BufEnter * LSClientEnsureCurrentWindowState
    autocmd WinEnter * timer_start(1, highlight.OnWinEnter)
    # Window local state is only correctly maintained for the current tab.
    autocmd TabEnter * util.WinDo('LSClientEnsureCurrentWindowState')
    # " Move is too heavy
    # " autocmd CursorMoved * call <SID>IfEnabled('lsc#cursor#onMove')
    autocmd CursorHold * IfEnabled(diagnostics.CursorOnHold)
    autocmd WinEnter * IfEnabled(diagnostics.CursorOnWinEnter)
    autocmd User LSCOnChangesFlushed IfEnabled(diagnostics.CursorOnChangesFlushed)
    autocmd WinLeave,InsertEnter * IfEnabled(cursor.Clean)
augroup END
