vim9script

import autoload "./signature_help.vim"

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

def IsCompletable(): bool
    var pos = col(".")
    var line = getline(".")
    var surr_chars = ""
    if len(line) > 2
        surr_chars =  line[pos - 4 : pos - 2]
    endif
    if len(trim(surr_chars)) > 2
        var banned_chars = [';', '{', '}', ',', '(', ')', '+']
        if surr_chars[2] == ':' && surr_chars[1] != ':'
            return false
        endif
        for i in banned_chars
            if surr_chars[0] == i || surr_chars[1] == i || surr_chars[2] == i
                return false
            endif
        endfor
        return true
    endif
    return false
enddef


export def InsertCharPre(): void
    g_next_char = v:char
enddef

def Sig_help_with_timer(): void
    signature_help.SignatureHelp()
    g_sighelp_timer = -1
enddef

def StartCompletion(isAuto: bool): void
    b:lsc_is_completing = true
    lsc#common#FileFlushChanges()
    var params = lsc#params#documentPosition()
    var server = lsc#server#forFileType(&filetype)
    lsc#common#Send(server.channel, 'textDocument/completion', params,
        lsc#common#GateResult('Complete',
            (result) => lsc#complete#OnResult(isAuto, result),
            (result) => lsc#complete#OnSkip(isAuto, bufnr('%'))
        )
    )
enddef

def TypedCharacter(): void
    if IsCompletable()
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
