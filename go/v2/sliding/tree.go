package sliding

import (
    "math"
)


const (
    leaf = math.MaxUint32
)


type tree uint32 // index to the node that is the tree's root

type node[A any] struct {
    left  tree     // left child
    right tree     // right child
    data  label[A] // aggregated value
}

type setup[A any] struct {
    in        <-chan A
    op        Op[option[A]]
    nodes     []node[A]
    recycles  []tree        // node indexes that are currently unused
    top       int
}


func newSetup[A any](in <-chan A, op Op[A], k int) *setup[A] {
    S := setup[A]{
        in:       in,
        op:       lift(op),
        nodes:    make([]node[A], k),
        recycles: make([]tree, k),
        top:      k,
    }
    // Every tree node is reusable for the empty tree.
    for i := 0; i < k; i++ {
        S.recycles[i] = tree(i)
        S.nodes[i].left, S.nodes[i].right = leaf, leaf
    }
    return &S
}


func (S *setup[A]) cleanup() {
    for i := 0; i < S.top; i++ {
        //S.nodes[i].data = none[A]()
        S.put(S.nodes[i].left)
        S.put(S.nodes[i].right)
        S.nodes[i].left, S.nodes[i].right = leaf, leaf
    }
}



// `get` returns a new node index.
func (S *setup[A]) get() tree {
    if S.top == 0 {
        // No reusables tree nodes.  Create new ones.
        k := len(S.nodes)
        S.nodes = append(S.nodes, make([]node[A], k)...)
        S.recycles = append(S.recycles, make([]tree, k)...)
        // Newly created nodes are reusables.
        S.top = k
        for i, j := 0, k; i < k; i, j = i + 1, j + 1 {
            S.recycles[i] = tree(j)
            S.nodes[j].left, S.nodes[j].right = leaf, leaf
        }
    }

    S.top--
    t := S.recycles[S.top]

    // Recycle children if they are not leafs.
    n := S.nodes[t]
    if n.left < tree(len(S.nodes)) {
        S.recycles[S.top] = n.left
        S.top++
        S.nodes[t].left = leaf
    }
    if n.right < tree(len(S.nodes)) {
        S.recycles[S.top] = n.right
        S.top++
        S.nodes[t].right = leaf
    }

    return t
}

// `put` marks the node index `t` as reusable.
func (S *setup[A]) put(t tree) {
    if t < tree(len(S.nodes)) {
        // If the tree is not a leaf, recycle it.
        S.recycles[S.top] = t
        S.top++
    }
}
