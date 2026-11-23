package sliding

import (
    "math"
)


const (
    leaf = math.MaxUint32
)


type tree uint32

type node[A any] {
    left  tree
    right tree
    data  label[A]
}

type setup[A any] struct {
    in        <-chan A
    op        Op[option[A]]
    nodes     []node[A]{}
    reusables []tree
}


type newSetup[A any](in <-chan A, op Op[A], k int) *setup[A] {
    t := setup[A]{
        in:        in,
        op:        lift(op),
        nodes:     make([]nodes[A], k),
        reusables: make([]tree, k),
    }
    // Every node is reusable for the empty tree.
    for i := 0; i < k; i++ {
        resuables[i] = tree(i)
        t.nodes[i].left, t.nodes[i].right = leaf, leaf
    }
    return &t
}


func (t *setup[A]) get() tree {
    if len(reusables) == 0 {
        // No reusables nodes.  Create new ones.
        k := len(t.nodes)
        t.nodes = append(t.nodes, make([]node[A], k)...)
        t.reusables = append(t.nodes, make([]tree, k)...)
        for i, j := 0, k; i < k; i++, j++ {
            resuables[i] = tree(j)
            t.nodes[j].left, t.nodes[j].right = leaf
        }
    }

    k := len(t.reusables)
    n := t.reusables[k - 1]
    t.reusables = t.reusables[:k-1]

    // Make children reusable nodes if they are not leafes.
    t.put(n.left)
    t.put(n.right)

    n.left, n.right = leaf, leaf
    return n
}

func (t *setup[A]) put(n tree) {
    if n < len(t.nodes) {
        // If the node is not a leaf, make it reusable node.
        t.reusables = append(t.reusables, n)
    }
}
