vim9script

def Node_new(tree: dict<any>, object_id: number, tree_item: dict<any>, parent: dict<any>): dict<any>
    tree.maxid += 1
    return {
        'id': tree.maxid,
        'tree': tree,
        'object': object_id,
        'tree_item': tree_item,
        'parent': parent,
        'collapsed': tree_item.collapsibleState ==? 'collapsed',
        'lazy_open': tree_item.collapsibleState !=? 'none',
        'children': [],
        }
enddef

def Node_get_tree_item_cb(node: dict<any>, object_id: number, tree_item: dict<any>): void
    var new_node = Node_new(node.tree, object_id, tree_item, node)
    add(node.children, new_node)
    Render(new_node.tree)
enddef

def Node_get_children_cb(node: dict<any>, childObjectList: list<number>): void
    for childObject in childObjectList
        node.tree.provider.getTreeItem((tree_item: dict<any>) => Node_get_tree_item_cb(node, childObject, tree_item), childObject)
    endfor
enddef

def Node_set_collapsed(node: dict<any>, collapsed: number): void
    node.collapsed = collapsed < 0 ? !node.collapsed : !!collapsed
enddef

def Search_subtree(node: dict<any>, Condition: func): list<dict<any>>
    if Condition(node)
        return [node]
    endif
    if len(node.children) < 1
        return []
    endif
    var result = []
    for child in node.children
        result = result + Search_subtree(child, Condition)
    endfor
    return result
enddef

def Node_exec(node: dict<any>): void
    if has_key(node.tree_item, 'command')
        node.tree_item.command()
    endif
enddef

# Return the string representation of the node. The {level} argument represents
# the depth level of the node in the tree and it is passed for convenience, to
# simplify the implementation and to avoid re-computing the depth.
def Node_render(node: dict<any>, level: number): string
    var indent = repeat(' ', 2 * level)
    var mark = '• '

    if len(node.children) > 0 || node.lazy_open != false
        mark = node.collapsed ? '▸ ' : '▾ '
    endif

    var label = split(node.tree_item.label, "\n")
    extend(node.tree.index, map(range(len(label)), (i, v) => node))

    var repr = indent .. mark .. label[0] .. join(map(label[1 : ], (_, l) => "\n" .. indent .. '  ' .. l))

    var lines = [repr]
    if !node.collapsed
        if node.lazy_open
            node.lazy_open = false
            node.tree.provider.getChildren((children) => Node_get_children_cb(node, children), {}, node.object)
        endif
        for child in node.children
            add(lines, Node_render(child, level + 1))
        endfor
    endif

    return join(lines, "\n")
enddef

def Tree_set_root_cb(tree: dict<any>, object_id: number, tree_item: dict<any>): void
    tree.maxid = -1
    tree.root = Node_new(tree, object_id, tree_item, {})
    Render(tree)
enddef

def Get_node_under_cursor(tree: dict<any>): dict<any>
    var index = min([line('.'), len(tree.index) - 1])
    return tree.index[index]
enddef

export def Tree_set_collapsed_under_cursor(node: dict<any>, collapsed: number): void
    var current_node = Get_node_under_cursor(node)
    Node_set_collapsed(current_node, collapsed)
    Render(node)
enddef

export def Tree_exec_node_under_cursor(node: dict<any>): void
    var current_node = Get_node_under_cursor(node)
    Node_exec(current_node)
enddef

export def Render(tree: dict<any>): void
    if &filetype !=# 'yggdrasil'
        return
    endif

    var cursor = getpos('.')
    tree.index = [-1]
    var text = Node_render(tree.root, 0)

    setlocal modifiable
    deletebufline(tree.bufnr, 1, "$")
    map(split(text, "\n"), (i, v) => append(i, [v]))

    setlocal nomodifiable

    setpos('.', cursor)
enddef

def Node_update(tree: dict<any>, object_id: number, tree_item: dict<any>): void
    for node in Search_subtree(tree.root, (n) => n.object == object_id)
        node.tree_item = tree_item
        node.children = []
        node.lazy_open = tree_item.collapsibleState !=? 'none'
    endfor
    Render(tree)
enddef

def Tree_update(node: dict<any>, node_entries: list<number>): void
    if len(node_entries) == 0 
        node.provider.getChildren((children_list: list<number>) => node.provider.getTreeItem(
                    \ (tree_item: dict<any>) => Tree_set_root_cb(node, children_list[0], tree_item), children_list[0]),
                    \ node.ignition, -1)
    else
        node.provider.getTreeItem((item) => Node_update(node, node_entries[0], item), node_entries[0])
    endif
enddef

export def Tree_wipe(self: dict<any>): void
    execute 'bwipeout ' .. self.bufnr
enddef

export def New_handle(provider: dict<any>, ignition: dict<any>): dict<any>
    return {
        'bufnr': bufnr('%'),
        'maxid': -1,
        'root': {},
        'index': [],
        'provider': provider,
        'set_collapsed_under_cursor': Tree_set_collapsed_under_cursor,
        'exec_node_under_cursor': Tree_exec_node_under_cursor,
        'update': Tree_update,
        'wipe': Tree_wipe,
        'ignition': ignition,
        }
enddef
