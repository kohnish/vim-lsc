vim9script

def LogLevelStrings(level: number): list<string>
    if level == 1
        return ['Error', 'lscDiagnosticError']
    elseif level == 2
        return ['Warning', 'lscDiagnosticWarning']
    elseif level == 3
        return ['Info', 'lscDiagnosticInfo']
    endif
    return ['Log', 'None']
enddef

def LogEchom(message: string, level: number): void
    var level_pair = LogLevelStrings(level)
    exec 'echohl ' .. level_pair[1]
    echom "[lsc: " .. level_pair[0] .. "] " .. message
    echohl None
enddef

export def Error(message: string): void
    LogEchom(message, 1)
enddef
