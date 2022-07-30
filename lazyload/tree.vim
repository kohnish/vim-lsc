vim9script

# Callback to retrieve the tree item representation of an object.
def Node_get_tree_item_cb(node: dict<any>, object_id: number, tree_item: dict<any>): void
    var new_node = Node_new(node.tree, object_id, tree_item, node)
    add(node.children, new_node)
    Render(new_node.tree)
enddef

# Callback to retrieve the children objects of a node.
def Node_get_children_cb(node: dict<any>, childObjectList: list<any>): void
    for childObject in childObjectList
        node.tree.provider.getTreeItem((tree_item: dict<any>) => Node_get_tree_item_cb(node, childObject, tree_item), childObject)
    endfor
enddef

# Set the node to be collapsed or expanded.
# When {collapsed} evaluates to 0 the node is expanded, when it is 1 the node is
# collapsed, when it is equal to -1 the node is toggled (it is expanded if it
# was collapsed, and vice versa).
def Node_set_collapsed(self: dict<any>, collapsed: number): void
    self.collapsed = collapsed < 0 ? !self.collapsed : !!collapsed
enddef

# Given a funcref {Condition}, return a list of all nodes in the subtree of
# {node} for which {Condition} evaluates to v:true.
def Search_subtree(node: dict<any>, Condition: func): list<any>
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

# Execute the action associated to a node
def Node_exec(self: dict<any>): void
    if has_key(self.tree_item, 'command')
        self.tree_item.command()
    endif
enddef

# Return the depth level of the node in the tree. The level is defined
# recursively: the root has depth 0, and each node has depth equal to the depth
# of its parent increased by 1.
def Node_level(self: dict<any>): number
    if self.parent == {}
        return 0
    endif
    return 1 + self.parent.level(self)
enddef

# Return the string representation of the node. The {level} argument represents
# the depth level of the node in the tree and it is passed for convenience, to
# simplify the implementation and to avoid re-computing the depth.
def Node_render(self: dict<any>, level: number): string
    var indent = repeat(' ', 2 * level)
    var mark = '• '

    if len(self.children) > 0 || self.lazy_open != false
        mark = self.collapsed ? '▸ ' : '▾ '
    endif

    var label = split(self.tree_item.label, "\n")
    extend(self.tree.index, map(range(len(label)), (i, v) => self))

    var repr = indent .. mark .. label[0]
    \          .. join(map(label[1 : ], (_, l) => "\n" .. indent .. '  ' .. l))

    var lines = [repr]
    if !self.collapsed
        if self.lazy_open
            self.lazy_open = false
            self.tree.provider.getChildren((children) => Node_get_children_cb(self, children), {}, self.object)
        endif
        for child in self.children
            add(lines, child.render(child, level + 1))
        endfor
    endif

    return join(lines, "\n")
enddef

# Insert a new node in the tree, internally represented by a unique progressive
# integer identifier {id}. The node represents a certain {object} (children of
# {parent}) belonging to a given {tree}, having an associated action to be
# triggered on execution defined by the function object {exec}. If {collapsed}
# is true the node will be rendered as collapsed in the view. If {lazy_open} is
# true, the children of the node will be fetched when the node is expanded by
# the user.
def Node_new(tree: dict<any>, object_id: number, tree_item: dict<any>, parent: dict<any>): dict<any>
    tree.maxid += 1
    return {
    \ 'id': tree.maxid,
    \ 'tree': tree,
    \ 'object': object_id,
    \ 'tree_item': tree_item,
    \ 'parent': parent,
    \ 'collapsed': tree_item.collapsibleState ==? 'collapsed',
    \ 'lazy_open': tree_item.collapsibleState !=? 'none',
    \ 'children': [],
    \ 'level': Node_level,
    \ 'exec': Node_exec,
    \ 'set_collapsed': Node_set_collapsed,
    \ 'render': Node_render
    \ }
enddef

# Callback that sets the root node of a given {tree}, creating a new node
# with a {tree_item} representation for the given {object}. If {status} is
# equal to 'success', the root node is set and the tree view is updated
# accordingly, otherwise nothing happens.
def Tree_set_root_cb(tree: dict<any>, object_id: number, tree_item: dict<any>): void
        tree.maxid = -1
        tree.root = Node_new(tree, object_id, tree_item, {})
        Render(tree)
enddef

# Return the node currently under the cursor from the given {tree}.
def Get_node_under_cursor(tree: dict<any>): dict<any>
    var index = min([line('.'), len(tree.index) - 1])
    return tree.index[index]
enddef

# Expand or collapse the node under cursor, and render the tree.
# Please refer to *Node_set_collapsed()* for details about the
# arguments and behaviour.
export def Tree_set_collapsed_under_cursor(self: dict<any>, collapsed: number): void
    var node = Get_node_under_cursor(self)
    node.set_collapsed(node, collapsed)
    Render(self)
enddef

# Run the action associated to the node currently under the cursor.
export def Tree_exec_node_under_cursor(self: dict<any>): void
    var node = Get_node_under_cursor(self)
    node.exec(node)
enddef

# Render the {tree}. This will replace the content of the buffer with the
# tree view. Clear the index, setting it to a list containing a guard
# value for index 0 (line numbers are one-based).
export def Render(tree: dict<any>): void
    if &filetype !=# 'yggdrasil'
        return
    endif

    var cursor = getpos('.')
    tree.index = [-1]
    var text = tree.root.render(tree.root, 0)

    setlocal modifiable
    # WIP
    #silent 1,$delete
    #append(line('$'), [text])
    #normal! G
    #execute "put " text
    #silent 0put=text
    #$d_
    deletebufline(tree.bufnr, 1, "$")
    map(split(text, "\n"), (i, v) => append(i, [v]))

    setlocal nomodifiable

    setpos('.', cursor)
enddef

# If {status} equals 'success', update all nodes of {tree} representing
# an {obect} with given {tree_item} representation.
def Node_update(tree: dict<any>, object_id: number, tree_item: dict<any>): void
    for node in Search_subtree(tree.root, (n) => n.object == object_id)
        node.tree_item = tree_item
        node.children = []
        node.lazy_open = tree_item.collapsibleState !=? 'none'
    endfor
    Render(tree)
enddef

# Update the view if nodes have changed. If called with no arguments,
# update the whole tree. If called with an {object} as argument, update
# all the subtrees of nodes corresponding to {object}.
def Tree_update(self: dict<any>, args: list<any>): void
    if len(args) == 0 
        self.provider.getChildren((children_list: list<any>) => self.provider.getTreeItem( 
                    \ (tree_item: dict<any>) => Tree_set_root_cb(self, children_list[0], tree_item), children_list[0]),
                    \ self.ignition, -1)
    else
        self.provider.getTreeItem((item) => Node_update(self, args[0], item), args[0])
    endif
enddef

# Destroy the tree view. Wipe out the buffer containing it.
export def Tree_wipe(self: dict<any>): void
    execute 'bwipeout ' .. self.bufnr
enddef

# Turns the current buffer into an Yggdrasil tree view. Tree data is retrieved
# from the given {provider}, and the state of the tree is stored in a
# buffer-local variable called g_tree_top.
#
# The {bufnr} stores the buffer number of the view, {maxid} is the highest
# known internal identifier of the nodes. The {index} is a list that
# maps line numbers to nodes.
export def New(provider: dict<any>, ignition: dict<any>): dict<any>
    var tree_top = {
    \ 'bufnr': bufnr('%'),
    \ 'maxid': -1,
    \ 'root': {},
    \ 'index': [],
    \ 'provider': provider,
    \ 'set_collapsed_under_cursor': Tree_set_collapsed_under_cursor,
    \ 'exec_node_under_cursor': Tree_exec_node_under_cursor,
    \ 'update': Tree_update,
    \ 'wipe': Tree_wipe,
    \ 'ignition': ignition,
    \ }

    return tree_top
enddef
