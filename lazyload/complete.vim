vim9script
# Use InsertCharPre to reliably know what is typed, but don't send the
# completion request until the file reflects the inserted character. Track typed
# characters in `s:next_char` and use CursorMovedI to act on the change.
# 
# Every typed character can potentially start a completion request:
# - "Trigger" characters (as specified during initialization) always start a
#   completion request when they are typed
# - Characters that match '\w' start a completion in words of at least length 3

var g_next_char = ""
var g_sighelp_timer = -1

export def InsertCharPre(): void
    g_next_char = v:char
enddef

def Sig_help_with_timer(): void
    lsc#common#GetSignatureHelp()
    g_sighelp_timer = -1
enddef

def StartCompletion(isAuto: bool): void
    b:lsc_is_completing = true
    lsc#file#flushChanges()
    var params = lsc#params#documentPosition()
    var server = lsc#server#forFileType(&filetype)
    lsc#common#Send(server.channel, 'textDocument/completion', params,
                \ lsc#common#GateResult('Complete',
                \ funcref(lsc#complete#OnResult, [isAuto]),
                \ [funcref(lsc#complete#OnSkip, [bufnr('%')])]))
enddef

def TypedCharacter(): void
    if lsc#common#IsCompletable()
        StartCompletion(true)
    endif
enddef

export def TextChanged(): void
    if &paste | return | endif
    if !g:lsc_enable_autocomplete | return | endif
    # This may be <BS> or similar if not due to a character typed
    if empty(g_next_char) | return | endif
    TypedCharacter()
    g_next_char = ''
    # Might help input becoming slower.
    if g_sighelp_timer == -1
        g_sighelp_timer = timer_start(200, (_) => Sig_help_with_timer())
    endif
enddef
