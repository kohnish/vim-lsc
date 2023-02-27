vim9script

import "./common.vim"

export def GetSignatureHelp(): void
    lsc#file#flushChanges()
    var params = lsc#params#documentPosition()
    var server = lsc#server#forFileType(&filetype)[0]
    try
        server.request('textDocument/signatureHelp', params, lsc#util#gateResult('SignatureHelp', ShowHelp))
    catch
    endtry
enddef

# sometimes it gets special instead of dict<any> for unknown reason
export def ShowHelp(signatureHelp: any): void
    # To avoid inlayhint disappearing for some reason
    if exists("b:inlayhint_prop_list") && !empty(b:inlayhint_prop_list)
        return
    endif

    if empty(signatureHelp)
        #call lsc#message#show('No signature help available')
        return
    endif
    var signatures = []
    if has_key(signatureHelp, 'signatures')
        if type(signatureHelp.signatures) == type([])
            signatures = signatureHelp.signatures
        endif
    endif

    if len(signatures) == 0
        return
    endif

    var active_signature = 0
    if has_key(signatureHelp, 'activeSignature')
        active_signature = signatureHelp.activeSignature
        if active_signature >= len(signatures)
            active_signature = 0
        endif
    endif

    var signature = get(signatures, active_signature)

    if !has_key(signature, 'label')
        return
    endif

    if !has_key(signature, 'parameters')
        if exists("b:sig_popup_id")
            popup_close(b:sig_popup_id)
        endif
        b:sig_popup_id = popup_atcursor(signature.label, {"line": "cursor-2"})
        return
    endif

    var active_param_len = 0
    var active_param_start_pos = 0
    if has_key(signatureHelp, 'activeParameter')
        var active_parameter = signatureHelp.activeParameter
        if active_parameter < len(signature.parameters) && has_key(signature.parameters[active_parameter], 'label')
            var current_parameter = signature.parameters[active_parameter].label
            active_param_len = len(current_parameter)
            active_param_start_pos = stridx(signature.label, current_parameter) + 1
        endif
    endif
    if exists("b:sig_popup_id")
       popup_close(b:sig_popup_id)
    endif
    b:sig_popup_id = popup_atcursor(signature.label, {"line": "cursor-2"})
    var popup_win_id = winbufnr(b:sig_popup_id)
    if !empty(prop_type_get('signature'))
        prop_type_delete('signature')
    endif
    prop_type_add('signature', {'bufnr': popup_win_id, 'highlight': 'PmenuSel'})
    if active_param_len > 0
        prop_add(1, active_param_start_pos, {'bufnr': popup_win_id, 'type': 'signature', 'length': active_param_len})
    endif
enddef

