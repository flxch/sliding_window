module Sliding (slidingWindow) where
       
-- Some general auxiliary functions 

swap f x y = f y x 

lift f (Just x) (Just y) = Just (f x y)
lift f _        _        = Nothing

-- Datatypes for the sliding window algorithm 

data Tree a =  Leaf | Node a (Tree a) (Tree a)
data Label a = Label {left :: Int, right :: Int, val :: a}

type Intermediate a = Tree (Label (Maybe a))
type Window = (Int,Int)

-- Selection functions for datatypes

leftIndex Leaf         = -1
leftIndex (Node l _ _) = left l
rightIndex Leaf         = -1
rightIndex (Node l _ _) = right l
value Leaf         = Nothing
value (Node l _ _) = val l

extract t = case value t of
              Nothing -> error "No value at tree's root."
              Just v  -> v
children Leaf            = error "No children at leaf."
children (Node _ t' t'') = (t', t'')

-- Auxiliary functions for the sliding window algorithm 

singleton (i,x) = Node l Leaf Leaf
  where l = Label {left = i, right = i, val = Just x}
                  
discharge Leaf            = Leaf
discharge (Node l t' t'') = Node l' t' t''
  where l' = Label {left = left l, right = right l, val = Nothing}

combine _  t'    Leaf  = t'
combine _  Leaf  t''   = t''
combine op t'    t''   = Node l (discharge t') t''
  where l = Label {left = leftIndex t', right = rightIndex t'', val = op (value t') (value t'')}
            
reusables :: Tree (Label a)          -- tree t 
             -> Int                  -- left bound l
             -> [Tree (Label a)]     -- list of t's maximal reusables subtrees
reusables t l 
  | l >  rightIndex t  = [] -- case could be checked before calling reusables in slide
  | l == leftIndex t   = [t] 
  | l >= leftIndex t'' = reusables t'' l
  | otherwise          = t'' : reusables t' l
    where (t', t'') = children t

slide :: (Maybe a -> Maybe a -> Maybe a)       -- lifted associative operator op
         -> [Intermediate a]                   -- list of singleton trees ys
         -> Intermediate a                     -- tree of previous window t
         -> Window                             -- window (l,r)
         -> ([Intermediate a], Intermediate a) -- remaining elements and updated tree
slide op ys t (l,r) = (rems, t')
    where (news, rems) = splitAt (1+r - (max l (1 + rightIndex t))) ys 
          reuses       = reusables t l
          t'           = foldl (swap (combine op)) Leaf ((reverse news) ++ reuses)

-- Sliding window algorithm 

slidingWindow :: (a -> a -> a)  -- associative operator op
                 -> [a]         -- list of elements xs = [x_0, ..., x_n-1]
                 -> [Window]    -- list of windows ws = [(l_0,r_0), ..., (l_k-1,r_k-1)]
                 -> [a]         
-- Conditions on windows: l_0<=l_2<=...<=l_k-1 and r_0<=r_1<=...<=r_k-1 and 0<=l_i<=r_i<n, 
--                          for all i = 0, ..., k-1
-- Return value: [y_0, ..., y_k-1] :: [a]
--               with y_i = x_{l_i} (op) x_{l_i+1} (op) ... (op) x_{r_i}, for all i = 0, ..., k-1
-- Note: the lists xs and ws can also be infinite

slidingWindow op xs ws = iterate singletons Leaf ws 
  where singletons          = map singleton (zip [0..] xs)
        iterate _  _ []     = []
        iterate ys t (w:ws) = let zs        = drop ((fst w) - 1-rightIndex t) ys 
                                  (ys', t') = slide (lift op) zs t w 
                              in                         
                                extract t' : iterate ys' t' ws