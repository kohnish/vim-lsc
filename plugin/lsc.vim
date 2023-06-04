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
import autoload "../lazyload/complete.vim"

g:_lsc_is_exiting = false

if !exists('g:lsc_servers_by_filetype')
    g:lsc_servers_by_filetype = {}
endif
if !exists('g:lsc_enable_autocomplete')
    g:lsc_enable_autocomplete = true
endif
if !exists('g:lsc_auto_completeopt')
    g:lsc_auto_completeopt = true
endif
if !exists('g:lsc_enable_snippet_support')
    g:lsc_enable_snippet_support = false
endif
if !exists('g:lsc_enable_popup_syntax')
    g:lsc_enable_popup_syntax = true
endif

if !hlexists('lscDiagnosticError')
    highlight link lscDiagnosticError Error
endif
if !hlexists('lscDiagnosticWarning')
    highlight link lscDiagnosticWarning SpellBad
endif
if !hlexists('lscDiagnosticInfo')
    highlight link lscDiagnosticInfo SpellCap
endif
if !hlexists('lscDiagnosticHint')
    highlight link lscDiagnosticHint SpellCap
endif
if !hlexists('lscReference')
    if hlexists('CtrlPMatch')
        highlight link lscReference CtrlPMatch
    else
        highlight link lscReference CursorColumn
    endif
endif
if !hlexists('lscCurrentParameter')
    highlight link lscCurrentParameter CursorColumn
endif

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
command! LSClientGoToDefinitionSplit lsc#reference#goToDefinition(<q-mods>, 1)
command! LSClientGoToDefinition lsc#reference#goToDefinition(<q-mods>, 0)
command! LSClientGoToDeclarationSplit lsc#reference#goToDeclaration(<q-mods>, 1)
command! LSClientGoToDeclaration lsc#reference#goToDeclaration(<q-mods>, 0)
command! LSClientFindReferences lsc#reference#findReferences()
command! LSClientFindImplementations lsc#reference#findImplementations()
command! -nargs=? LSClientShowHover lsc#reference#hover()
command! LSClientDocumentSymbol lsc#reference#documentSymbols()
command! -nargs=? LSClientWorkspaceSymbol lsc#search#workspaceSymbol(<q-args>)
command! -nargs=? LSClientFindCodeActions lsc#edit#findCodeActions(lsc#edit#filterActions(<args>))
command! LSClientRestartServer lsc#server#exit(v:true)
command! LSClientDisable lsc#server#exit(v:false)
command! LSClientEnable lsc#server#exit(v:true)
command! -nargs=? LSClientRename lsc#edit#rename(<args>)

def IsChannelActiveForFileType(filetype: string): bool
    try
        return ch_status(lsc#server#servers()[g:lsc_servers_by_filetype[filetype]].channel) == "open"
    catch
    endtry
    return false
enddef

def HasConfingForFileType(filetype: string): bool
    try
        var server = lsc#server#servers()[g:lsc_servers_by_filetype[filetype]]
        return get(server.config, 'enabled', true)
    catch
    endtry
    return v:false
enddef

def OnOpen(): void
    if exists('g:lsc_disabled') && g:lsc_disabled | return | endif
    if !&modifiable | return | endif
    if expand('%') =~# '\vfugitive:///' | return | endif
    if !has_key(g:lsc_servers_by_filetype, &filetype)
        var cfg = {}
        if exists('g:lsc_server_commands')
            cfg = g:lsc_server_commands
        endif
        try
            lsc#server#RegisterLanguageServer(&filetype, cfg[&filetype])
        catch
        endtry
    endif
    if !HasConfingForFileType(&filetype) | return | endif
    lsc#config#mapKeys()
    lsc#file#onOpen()
enddef

# This should only be used for the autocommands which are known to only fire for
# the current buffer where '&filetype' can be trusted.
def IfEnabled(Cb: func): void
    if !has_key(g:lsc_servers_by_filetype, &filetype) | return | endif
    if !&modifiable | return | endif
    if !IsChannelActiveForFileType(&filetype) | return | endif
    Cb()
enddef

def EnsureBufState()
    highlight.EnsureCurrentWindowState()
enddef

def EnsureWinState()
    util.WinDo('LSClientEnsureCurrentWindowState')
enddef

def OnWinEnterTimer()
    timer_start(1, (timer_id) => highlight.HighlightOnWinEnter())
enddef

def OnClose()
    if g:_lsc_is_exiting | return | endif
    var filetype = getbufvar(str2nr(expand('<abuf>')), '&filetype')
    if !has_key(g:lsc_servers_by_filetype, filetype) | return | endif
    var full_path = lsc#file#normalize(expand('<afile>:p'))
    lsc#file#onClose(full_path, filetype)
enddef

def OnWrite(): void
    var filetype = getbufvar(str2nr(expand('<abuf>')), '&filetype')
    var full_path = expand('<afile>:p')
    lsc#file#onWrite(full_path, filetype)
enddef

augroup LSC
    autocmd!
    autocmd BufEnter * IfEnabled(EnsureBufState)
    autocmd WinEnter * IfEnabled(OnWinEnterTimer)
    # Window local state is only correctly maintained for the current tab.
    autocmd TabEnter * IfEnabled(EnsureWinState)
    # " Move is too heavy
    # " autocmd CursorMoved * call <SID>IfEnabled('lsc#cursor#onMove')
    autocmd CursorHold * IfEnabled(diagnostics.CursorOnHold)
    autocmd WinEnter * IfEnabled(diagnostics.CursorOnWinEnter)
    autocmd User LSCOnChangesFlushed IfEnabled(diagnostics.CursorOnChangesFlushed)
    autocmd WinLeave,InsertEnter * IfEnabled(cursor.Clean)
    autocmd TextChangedI * IfEnabled(complete.TextChanged)
    autocmd InsertCharPre * IfEnabled(complete.InsertCharPre)
    autocmd TextChanged,TextChangedI,CompleteDone * IfEnabled(lsc#common#FileOnChange)
    autocmd BufLeave * IfEnabled(lsc#common#FileFlushChanges)
    autocmd BufUnload * IfEnabled(OnClose)
    autocmd BufNewFile,BufReadPost * OnOpen()
    autocmd BufWritePost * IfEnabled(OnWrite)
    autocmd VimLeave * lsc#server#exit(v:false)
    if exists('##ExitPre')
        autocmd ExitPre * g:_lsc_is_exiting = v:true
    endif
augroup END
