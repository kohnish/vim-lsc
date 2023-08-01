vim9script

var g_callback_gates = {}

export def SkipCb(result: dict<any>): void
    return
enddef

def Gated(name: string, gate: number, old_pos: list<number>, OnCall: func, OnSkip: func, result: dict<any>): void
    if g_callback_gates[name] != gate || old_pos != getcurpos()
        OnSkip(result)
    else
        OnCall(result)
    endif
enddef

export def CreateOrGet(name: string, Callback: func, OnSkip: func): func
    if !has_key(g_callback_gates, name)
        g_callback_gates[name] = 0
    else
        g_callback_gates[name] += 1
    endif
    return funcref(Gated, [name, g_callback_gates[name], getcurpos(), Callback, OnSkip])
enddef
