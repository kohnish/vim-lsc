vim9script

def Node_new(tree: dict<any>, object_id: number, tree_item: dict<any>): dict<any>
    return {
        'tree': tree,
        'object': object_id,
        'tree_item': tree_item,
        'collapsed': tree_item.collapsibleState ==? 'collapsed',
        'lazy_open': tree_item.collapsibleState !=? 'none',
        'children': [],
        }
enddef

def Render_children_nodes(node: dict<any>, children_list: list<number>): void
    for object_id in children_list
        node.tree.provider.getTreeItem((tree_item: dict<any>) => add(node.children, Node_new(node.tree, object_id, tree_item)), object_id)
    endfor
    Write_tree(node.tree)
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

def Node_to_str(node: dict<any>, level: number): string
    var mark = '• '
    if len(node.children) > 0 || node.lazy_open != false
        mark = node.collapsed ? '▸ ' : '▾ '
    endif
    var indent = repeat(' ', 2 * level)
    var label = split(node.tree_item.label, "\n")
    extend(node.tree.index, map(range(len(label)), (i, v) => node))
    var repr = indent .. mark .. label[0] .. join(map(label[1 : ], (_, l) => "\n" .. indent .. '  ' .. l))
    var lines = [repr]
    if !node.collapsed
        if node.lazy_open
            node.lazy_open = false
            node.tree.provider.getChildren((children) => Render_children_nodes(node, children), {}, node.object)
        endif
        for child in node.children
            add(lines, Node_to_str(child, level + 1))
        endfor
    endif
    return join(lines, "\n")
enddef

def Render_root_node(tree: dict<any>, object_id: number, tree_item: dict<any>): void
    tree.root = Node_new(tree, object_id, tree_item)
    Write_tree(tree)
enddef

def Get_node_under_cursor(tree: dict<any>): dict<any>
    var index = min([line('.'), len(tree.index) - 1])
    return tree.index[index]
enddef

def Node_update(tree: dict<any>, object_id: number, tree_item: dict<any>): void
    for node in Search_subtree(tree.root, (n) => n.object == object_id)
        node.tree_item = tree_item
        node.children = []
        node.lazy_open = tree_item.collapsibleState !=? 'none'
    endfor
    Write_tree(tree)
enddef

export def Tree_set_collapsed_under_cursor(tree: dict<any>, collapsed: number): void
    Node_set_collapsed(Get_node_under_cursor(tree), collapsed)
    Write_tree(tree)
enddef

export def Tree_exec_node_under_cursor(tree: dict<any>): void
    Node_exec(Get_node_under_cursor(tree))
enddef

export def Write_tree(tree: dict<any>): void
    if bufnr('') != tree.bufnr
        return
    endif

    var cursor = getpos('.')
    tree.index = [-1]
    var text = Node_to_str(tree.root, 0)

    setlocal modifiable
    deletebufline(tree.bufnr, 1, "$")
    map(split(text, "\n"), (i, v) => append(i, [v]))
    setlocal nomodifiable

    setpos('.', cursor)
enddef

export def Tree_update(tree: dict<any>, node_entries: list<number>): void
    if len(node_entries) == 0 
        tree.provider.getChildren((children_list: list<number>) => tree.provider.getTreeItem(
                    \ (tree_item: dict<any>) => Render_root_node(tree, children_list[0], tree_item), children_list[0]),
                    \ tree.ignition, -1)
    else
        tree.provider.getTreeItem((item) => Node_update(tree, node_entries[0], item), node_entries[0])
    endif
enddef

export def Tree_wipe(tree: dict<any>): void
    execute 'bwipeout ' .. tree.bufnr
enddef

export def New_tree(provider: dict<any>, ignition: dict<any>): dict<any>
    return {
        'bufnr': bufnr('%'),
        'root': {},
        'index': [],
        'provider': provider,
        'ignition': ignition,
        }
enddef
