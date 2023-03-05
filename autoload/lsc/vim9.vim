vim9script

import autoload "../../lazyload/gates.vim"
import autoload "../../lazyload/format.vim"
import autoload "../../lazyload/inlayhint.vim"
import autoload "../../lazyload/hierarchy.vim"
import autoload "../../lazyload/switch_source_header.vim"
import autoload "../../lazyload/signature_help.vim"
import autoload "../../lazyload/highlight.vim"
import autoload "../../lazyload/diagnostics.vim"

export def DiagnosticsShowInQuickFix(): void
    diagnostics.ShowInQuickFix()
enddef
export def DiagnosticsSetForFile(file_path: string, diags: list<any>): void
    diagnostics.SetForFile(file_path, diags)
enddef

export def HighlightsUpdateDisplayed(buf_number: number): void
    highlight.UpdateDisplayed(buf_number)
enddef

export def HighlightsUpdate(): void
    highlight.Update()
enddef

export def HighlightsClear(): void
    highlight.Clear()
enddef

export def GateResult(name: string, Callback: func, vargs: list<any>): func
    return gates.CreateOrGet(name, Callback, vargs)
enddef

export def RunFormat(): void
    format.Format()
enddef

export def ToggleInlayHint(): void
    inlayhint.InlayHint()
enddef

export def PrepCallHierarchy(mode: string): void
    hierarchy.CallHierarchy(mode)
enddef

export def SwitchSourceHeader(): void
    switch_source_header.Alternative()
enddef

export def GetSignatureHelp(): void
    signature_help.SignatureHelp()
enddef
