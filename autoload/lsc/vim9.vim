vim9script

import autoload "../../lazyload/gates.vim"
import autoload "../../lazyload/format.vim"
import autoload "../../lazyload/inlayhint.vim"
import autoload "../../lazyload/hierarchy.vim"
import autoload "../../lazyload/switch_source_header.vim"

export def GateResult(name: string, Callback: func, vargs: list<any>): func
    return gates.CreateOrGet(name, Callback, vargs)
enddef

export def Format(): void
    format.Format()
enddef

export def ToggleInlayHint(): void
    inlayhint.ToggleInlayHint()
enddef

export def PrepCallHierarchy(mode: string): void
    hierarchy.PrepCallHierarchy(mode)
enddef

export def SwitchSourceHeader(): void
    switch_source_header.SwitchSourceHeader()
enddef
