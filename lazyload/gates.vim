vim9script

var g_callback_gates = {}
def Gated(name: string, gate: number, old_pos: list<number>, OnCall: func, on_skip: bool, vargs: list<any>): void
    if g_callback_gates[name] != gate || old_pos != getcurpos()
        if type(on_skip) == 2
            OnCall(on_skip, vargs)
        endif
    else
        OnCall(vargs)
    endif
enddef

export def CreateOrGet(name: string, Callback: func, vargs: list<any>): func
    if !has_key(g_callback_gates, name)
        g_callback_gates[name] = 0
    else
        g_callback_gates[name] += 1
    endif
    var gate = g_callback_gates[name]
    var old_pos = getcurpos()
    if len(vargs) >= 1 && type(vargs[1]) == 2
        return funcref(Gated, [name, gate, old_pos, Callback, vargs[1]])
    endif
    return funcref(Gated, [name, gate, old_pos, Callback, false])
enddef
