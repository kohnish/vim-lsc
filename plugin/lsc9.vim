vim9script

import autoload "../lazyload/hierarchy.vim"
import autoload "../lazyload/diagnostics.vim"
import autoload "../lazyload/switch_source_header.vim"
import autoload "../lazyload/inlayhint.vim"
import autoload "../lazyload/signature_help.vim"
import autoload "../lazyload/format.vim"
import autoload "../lazyload/highlight.vim"
import autoload "../lazyload/util.vim"

command! LSClientDiagnosticHover lsc#diag#DiagHover()

command! LSClientIncomingCalls hierarchy.CallHierarchy("incoming")
command! LSClientOutgoingCalls hierarchy.CallHierarchy("outgoing")
command! LSClientSwitchSourceHeader switch_source_header.Alternative()
command! LSClientAllDiagnostics diagnostics.ShowInQuickFix()
command! LSClientSignatureHelp signature_help.SignatureHelp()
command! LSClientFormat format.Format()
command! LSClientInlayHintToggle inlayhint.InlayHint()
command! LSClientEnsureCurrentWindowState highlight.EnsureCurrentWindowState()

augroup LSC9
    autocmd!
    autocmd BufEnter * LSClientEnsureCurrentWindowState
    autocmd WinEnter * timer_start(1, highlight.OnWinEnter)
    # Window local state is only correctly maintained for the current tab.
    autocmd TabEnter * util.WinDo('LSClientEnsureCurrentWindowState')
augroup END
