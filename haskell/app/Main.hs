module Main (main) where

import System.Environment(getArgs, getProgName)
import System.Console.GetOpt
import System.Random

import Sliding -- import the function "slidingWindow"

-- A naive sliding-window algorithm:
        
naive op xs ws = 
  [ foldr op (head sl) (tail sl) | (l,r) <- ws, 
                                   sl    <- [take (r-l+1) (drop l xs)] ]

-- A costly way to compute a+b:

prime :: Int -> Bool
prime n = [1,n] == [ x | x <- [1..n], n `mod` x == 0 ]

expensive a b = let a' = reverse (take (a+b+40) (filter prime [1..]))
                    b' = reverse (take (b+a+40) (filter prime [1..]))
                    c  = -length (reverse (take 40 (filter prime [1..]))) + 
                         (length (reverse (a' ++ b')) `div` 2)
                in c
  
-- Command-line usage: 
-- * compile with "ghc --make -o sliding Main.hs"
-- * compile with "ghc --make -prof -auto-all -o sliding Main.hs" for profiling;
--   run with "sliding [OPTIONS] +RTS -p"

main :: IO ()
main = do prg <- getProgName
          args <- getArgs
          case getOpt RequireOrder options args of
            (flags, [],      [])   -> do let (s,l,algo,op,r) = foldr setParams defParams flags
                                         setStdGen (mkStdGen r)                                             
                                         zerosones <- sequence (replicate (l+s) (randomRIO (0,1)))
                                         let output = algo op zerosones [ (i,i+s-1) | i <- [0..l-1] ]
                                         putStr $ show output
                                         putStr "\n"
            (_,     nonOpts, [])   -> error $ "unrecognized arguments: " ++ 
                                      unwords nonOpts ++ "\n" ++
                                      usageInfo (header prg) options
            (_,     _,       msgs) -> error $ concat msgs ++ 
                                      usageInfo (header prg) options
          return ()


header name = "Usage: " ++ name ++ " [OPTION...]"

data Flag = Size String | Length String | Algo String | Op String | Random String

options :: [OptDescr Flag]
options = [
    Option ['s'] ["size"]     (ReqArg Size "number")        "window size (default=10)",
    Option ['l'] ["length"]   (ReqArg Length "number")      "stream length (default=100)",
    Option ['a'] ["algo"]     (ReqArg Algo "naive|slide")   "algorithm (default=naive)",
    Option ['o'] ["operator"] (ReqArg Op "expensive|cheap") "operator (default=expensive)",
    Option ['r'] ["random"]   (ReqArg Random "number")      "random seed (default=0)"
  ]
          
defParams = (10,100,naive,expensive,0)
  
setParams (Size s)         (_,l,algo,op,r) = (read s,l,algo,op,r)
setParams (Length l)       (s,_,algo,op,r) = (s,read l,algo,op,r)
setParams (Algo "naive")   (s,l,_,op,r)    = (s,l,naive,op,r)
setParams (Algo "slide")   (s,l,_,op,r)    = (s,l,slidingWindow,op,r)
setParams (Algo _)         (_,_,_,_,_)     = error "unknown algorithm"
setParams (Op "expensive") (s,l,algo,_,r)  = (s,l,algo,expensive,r)
setParams (Op "cheap")     (s,l,algo,_,r)  = (s,l,algo,(+),r)
setParams (Op _)           (_,_,_,_,_)     = error "unknown operator"
setParams (Random r)       (s,l,algo,op,_) = (s,l,algo,op,read r)                
