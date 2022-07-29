vim9script

import autoload "../../lazyload/tree.vim"

def OpenIncomingCallNode(current_node_num: number, params: dict<any>, results: list<any>): void
    if len(results) == 0
        return
    endif
    var len_results = len(results)
    var len_tree = len(b:tree)
    b:tree[current_node_num] = range(len_tree, len_tree + len_results - 1)
    var counter = 0
    for i in b:tree[current_node_num]
        b:tree[i] = []
        b:nodes[i] = { "query": {"item": results[counter]["from"] } }
        counter = counter + 1
    endfor
    b:handle.update(b:handle, range(current_node_num, current_node_num + len(b:tree[current_node_num]) - 1))
    tree.Tree_set_collapsed_under_cursor(b:handle, 0)
enddef

def ShowFuncOnBuffer(info: dict<any>): void
    var cur = win_findbuf(bufnr(''))[0]
    win_gotoid(b:ctx["original_win_id"])
    execute "edit " .. info["uri"]
    cursor(info["selectionRange"]["start"]["line"] + 1, info["selectionRange"]["start"]["character"] + 1)
    win_gotoid(cur)
enddef

# Action to be performed when executing an object in the tree.
def Command_callback(id: number): void
    tree.Tree_set_collapsed_under_cursor(b:handle, 0)
    if has_key(b:nodes, id)
        ShowFuncOnBuffer(b:nodes[id]["query"]["item"])
    endif
    if has_key(b:tree, id) && len(b:tree[id]) != 0
        return
    endif
    var param = b:nodes[id]["query"]
    lsc#server#userCall_with_server(b:ctx["server"], 'callHierarchy/incomingCalls', param, function(OpenIncomingCallNode, [id, param]))
enddef

# Auxiliary function to map each object to its parent in the tree.
# return type????
def Number_to_parent(id: number): dict<any>
    for [parent, children] in items(b:tree)
        if index(children, id) > 0
            return parent
        endif
    endfor
    return {}
enddef

# Auxiliary function to produce a minimal tree item representation for a given
# object (i.e. a given integer number).
#
# The four mandatory fields for the tree item representation are:
#  * id: unique string identifier for the node in the tree
#  * collapsibleState: string value, equal to:
#     + 'collapsed' for an inner node initially collapsed
#     + 'expanded' for an inner node initially expanded
#     + 'none' for a leaf node that cannot be expanded nor collapsed
#  * command: function object that takes no arguments, it runs when a node is
#    executed by the user
#  * labe string representing the node in the view
def Number_to_treeitem(id: number): dict<any>
    var label = b:nodes[id]["query"]["item"]["name"]
    return {
    \   'id': string(id),
    \   'command': () => Command_callback(id),
    \   'collapsibleState': len(b:tree[id]) > 0 ? 'collapsed' : 'none',
    \   'label': label,
    \ }
enddef

# The getChildren method can be called with no object argument, in that case it
# returns the root of the tree, or with one object as second argument, in that
# case it returns a list of objects that are children to the given object.
#def GetChildren(Callback: func, args: list<any>): void
def GetChildren(Callback: func, ignition: dict<any>, object_id: number): void
    if !empty(ignition)
        b:ctx = {
            "server": ignition["server"],
            "original_win_id": ignition["original_win_id"]
            }
        b:nodes = {
            0: { "query": ignition["query"] }
            }
        b:tree = {
            0: [],
            }
    endif
    var children = [0]
    #if has_key(current_tree, 'object')
    if object_id != -1
        if has_key(b:tree, object_id)
            children = b:tree[object_id]
        else
            Callback('failure')
        endif
    endif
    Callback('success', children)
enddef

# The getParent method returns the parent of a given object.
def GetParent(Callback: func, object_id: number): void
    Callback('success', Number_to_parent(object_id))
enddef

# The getTreeItem returns the tree item representation of a given object.
def GetTreeItem(Callback: func, object_id: number): void
    Callback('success', Number_to_treeitem(object_id))
enddef

export def MutateNode(mode: string): void
    if mode == "toggle"
        tree.Tree_set_collapsed_under_cursor(b:handle, -1)
    elseif mode == "wipe"
        tree.Tree_wipe(b:handle)
    elseif mode == "open"
        tree.Tree_set_collapsed_under_cursor(b:handle, 0)
    elseif mode == "close"
        tree.Tree_set_collapsed_under_cursor(b:handle, 1)
    elseif mode == "exec"
        tree.Tree_exec_node_under_cursor(b:handle)
    endif
enddef

# Apply local settings to an Yggdrasil buffer
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

    nnoremap <silent> <buffer> <Plug>(yggdrasil-toggle-node) <ScriptCmd>MutateNode("toggle")<CR>
    nnoremap <silent> <buffer> <Plug>(yggdrasil-open-node) <ScriptCmd>MutateNode("open")<CR>
    nnoremap <silent> <buffer> <Plug>(yggdrasil-close-node) <ScriptCmd>MutateNode("close")<CR>
    nnoremap <silent> <buffer> <Plug>(yggdrasil-execute-node) <ScriptCmd>MutateNode("exec")<CR>
    nnoremap <silent> <buffer> <Plug>(yggdrasil-wipe-tree) <ScriptCmd>MutateNode("wipe")<CR>

    if !exists('g:yggdrasil_no_default_maps')
        nmap <silent> <buffer> o    <Plug>(yggdrasil-toggle-node)
        nmap <silent> <buffer> <CR> <Plug>(yggdrasil-execute-node)
        nmap <silent> <buffer> p <Plug>(yggdrasil-execute-node)
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

export def Window(ignition: dict<any>): void
    var provider = {
        'getChildren': GetChildren,
        'getParent': GetParent,
        'getTreeItem': GetTreeItem,
        }

    var buf_name = "Incoming call hierarchy"
    if !has('g:lsc_multi_hierarchy_buf') || !g:lsc_multi_hierarchy_buf
        DeleteBufByPrefix(buf_name)
    endif
    topleft vnew
    execute "file " .. buf_name .. " [" .. bufnr('') .. "]"
    vertical resize 45
    b:handle = tree.New(provider, ignition)
    augroup vim_yggdrasil
        autocmd!
        autocmd FileType yggdrasil Filetype_syntax() | Filetype_settings()
        autocmd BufEnter <buffer> tree.Render(b:handle)
    augroup END

    setlocal filetype=yggdrasil

    b:handle.update(b:handle, [])
enddef

def IncomingCallReq(results: list<any>): void
    if len(results) > 0
        var params = {"item": results[0]}
        var ignition = {
            "server": lsc#server#forFileType(&filetype)[0],
            "original_win_id": win_getid(),
            "query": params,
            }
        Window(ignition)
    endif
enddef

export def PrepCallHierarchy(): void
    lsc#file#flushChanges()
    var params = lsc#params#documentPosition()
    lsc#server#userCall('textDocument/prepareCallHierarchy', params, IncomingCallReq)
enddef
