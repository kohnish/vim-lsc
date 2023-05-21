vim9script

import autoload "./server.vim"
import autoload "./util.vim"
import autoload "./log.vim"
import autoload "./tree.vim"

def OpenHierarchyCallNode(current_node_num: number, params: dict<any>, msg: dict<any>): void
    var results = msg["result"]
    if len(results) == 0
        return
    endif
    var len_results = len(results)
    var len_tree = len(b:integer_tree)
    b:integer_tree[current_node_num] = range(len_tree, len_tree + len_results - 1)
    var counter = 0
    for i in b:integer_tree[current_node_num]
        b:integer_tree[i] = []
        b:nodes[i] = {}
        b:nodes[i]["query"] = {"item": results[counter][b:ctx["hierarchy_result_key"]] }
        if has_key(results[counter], "fromRanges")
            b:nodes[i]["info"] = {"item": results[counter]["fromRanges"][0] }
            b:nodes[i]["info"]["item"]["uri"] = results[counter]["from"]["uri"]
        endif
        counter = counter + 1
    endfor
    tree.Tree_update(b:tree, [current_node_num])
    tree.Tree_set_collapsed_under_cursor(b:tree, 0)
enddef

def ShowFuncOnBuffer(info: dict<any>): void
    var cur = win_findbuf(bufnr(''))[0]
    win_gotoid(b:ctx["original_win_id"])
    execute "edit " .. info["uri"]
    cursor(info["selectionRange"]["start"]["line"] + 1, info["selectionRange"]["start"]["character"] + 1)
    win_gotoid(cur)
enddef

def ShowRefOnBuffer(info: dict<any>): void
    var cur = win_findbuf(bufnr(''))[0]
    win_gotoid(b:ctx["original_win_id"])
    execute "edit " .. info["uri"]
    cursor(info["start"]["line"] + 1, info["start"]["character"] + 1)
    win_gotoid(cur)
enddef

def Command_callback(id: number): void
    tree.Tree_set_collapsed_under_cursor(b:tree, 0)
    if has_key(b:nodes, id)
        if has_key(b:nodes[id], "info")
            ShowRefOnBuffer(b:nodes[id]["info"]["item"])
        else
            ShowFuncOnBuffer(b:nodes[id]["query"]["item"])
        endif
    endif
    if has_key(b:integer_tree, id) && len(b:integer_tree[id]) != 0
        return
    endif
    var param = b:nodes[id]["query"]
    server.LspRequestWithServer(b:ctx["server"], b:ctx["hierarchy_call"], param, function(OpenHierarchyCallNode, [id, param]))
enddef

def Number_to_treeitem(id: number): dict<any>
    var label = b:nodes[id]["query"]["item"]["name"]
    return {
                \ 'command': () => Command_callback(id),
                \ 'collapsibleState': len(b:integer_tree[id]) > 0 ? 'collapsed' : 'none',
                \ 'label': label,
                \ }
enddef

def GetChildren(Render_children_nodes: func, ignition: dict<any>, object_id: number): void
    if !empty(ignition)
        b:ctx = {
                    \ "server": ignition["server"],
                    \ "original_win_id": ignition["original_win_id"],
                    \ "hierarchy_call": ignition["hierarchy_call"],
                    \ "hierarchy_result_key": ignition["hierarchy_result_key"],
                    \ }
        b:nodes = {
                    \ 0: { "query": ignition["query"] }
                    \ }
        b:integer_tree = {
                    \ 0: [],
                    \ }
    endif
    var children = [0]
    if object_id != -1
        if has_key(b:integer_tree, object_id)
            children = b:integer_tree[object_id]
        endif
    endif
    Render_children_nodes(children)
enddef

def GetTreeItem(Render_node: func, object_id: number): void
    Render_node(Number_to_treeitem(object_id))
enddef

def Filetype_settings(): void 
    setlocal bufhidden=wipe
    setlocal buftype=nofile
    setlocal foldcolumn=0
    setlocal foldmethod=manual
    setlocal nobuflisted
    setlocal nofoldenable
    setlocal nolist
    setlocal nomodifiable
    setlocal nonumber
    setlocal norelativenumber
    setlocal nospell
    setlocal noswapfile
    setlocal nowrap

    nnoremap <silent> <buffer> <Plug>(yggdrasil-toggle-node) <ScriptCmd>tree.Tree_set_collapsed_under_cursor(b:tree, -1)<CR>
    nnoremap <silent> <buffer> <Plug>(yggdrasil-open-node) <ScriptCmd>tree.Tree_set_collapsed_under_cursor(b:tree, 0)<CR>
    nnoremap <silent> <buffer> <Plug>(yggdrasil-close-node) <ScriptCmd>tree.Tree_set_collapsed_under_cursor(b:tree, 1)<CR>
    nnoremap <silent> <buffer> <Plug>(yggdrasil-execute-node) <ScriptCmd>tree.Tree_exec_node_under_cursor(b:tree)<CR>
    nnoremap <silent> <buffer> <Plug>(yggdrasil-wipe-tree) <ScriptCmd>tree.Tree_wipe(b:tree)<CR>

    if !exists('g:yggdrasil_no_default_maps')
        nmap <silent> <buffer> o    <Plug>(yggdrasil-toggle-node)
        nmap <silent> <buffer> <CR> <Plug>(yggdrasil-execute-node)
        nmap <silent> <buffer> q    <Plug>(yggdrasil-wipe-tree)
    endif
enddef

def Filetype_syntax(): void
    syntax clear
    syntax match YggdrasilMarkLeaf        "•" contained
    syntax match YggdrasilMarkCollapsed   "▸" contained
    syntax match YggdrasilMarkExpanded    "▾" contained
    syntax match YggdrasilNode            "\v^(\s|[▸▾•])*.*" contains=YggdrasilMarkLeaf,YggdrasilMarkCollapsed,YggdrasilMarkExpanded

    highlight def link YggdrasilMarkLeaf        Type
    highlight def link YggdrasilMarkExpanded    Type
    highlight def link YggdrasilMarkCollapsed   Macro
enddef

def DeleteBufByPrefix(name: string): void
    for i in tabpagebuflist()
        if buffer_name(i)[0 : len(name) - 1] ==# name
            execute "bdelete " .. i
            break
        endif
    endfor
enddef

def OpenTreeWindow(ignition: dict<any>): void
    var provider = {
                \ 'getChildren': GetChildren,
                \ 'getTreeItem': GetTreeItem,
                \ }

    var buf_name_prefix = "Call hierarchy ("
    var buf_name = buf_name_prefix .. ignition["mode"] .. ")"
    if !exists("g:lsc_allow_multi_call_hierarchy_buf") || !g:lsc_allow_multi_call_hierarchy_buf
        DeleteBufByPrefix(buf_name_prefix)
    endif
    topleft vnew
    execute "file " .. buf_name .. " [" .. bufnr('') .. "]"
    vertical resize 45
    b:tree = tree.New_tree(provider, ignition)
    augroup vim_yggdrasil
        autocmd!
        autocmd FileType yggdrasil Filetype_syntax() | Filetype_settings()
        autocmd BufEnter <buffer> tree.Write_tree(b:tree)
    augroup END

    setlocal filetype=yggdrasil
    b:vim9_lsc_hierarchy_buf_name = buf_name
    setlocal statusline=\ \ %{b:vim9_lsc_hierarchy_buf_name}

    tree.Tree_update(b:tree, [])
enddef

def PrepHierarchyCb(mode_info: dict<any>, msg: dict<any>): void
    var results = msg["result"]
    if len(results) > 0
        var ignition = {
                    \ "server": server.ServerForFileType(&filetype),
                    \ "original_win_id": win_getid(),
                    \ "query": {"item": results[0]},
                    \ "mode": mode_info["name"],
                    \ "hierarchy_call": mode_info["call_name"],
                    \ "hierarchy_result_key": mode_info["result_key"],
                    \ }
        OpenTreeWindow(ignition)
    else
        log.Error("No results for " .. mode_info["call_name"])
    endif
enddef

export def CallHierarchy(mode: string): void
    var prep_req = "textDocument/prepareCallHierarchy"
    var hierarchy_call = "callHierarchy/incomingCalls"
    var result_key = "from"
    if mode == "outgoing"
        hierarchy_call = "callHierarchy/outgoingCalls"
        result_key = "to"
    endif
    var mode_info = {
                \ "name": mode,
                \ "call_name": hierarchy_call,
                \ "result_key": result_key
                \ }
    server.LspRequest(prep_req, util.DocPos(), function(PrepHierarchyCb, [mode_info]))
enddef
