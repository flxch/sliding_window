import System.Environment (getArgs)
import System.Random (mkStdGen, randomRs)
import System.Exit (die)
import Data.List (foldl1')
import Data.Time.Clock.POSIX (getPOSIXTime)
import Sliding (slidingWindow)
import Text.Printf (printf)

genWindows :: String -> Int -> Int -> Int -> Int -> Maybe FilePath -> IO [(Int,Int)]
genWindows mode n k stride seed mfile = case mode of
    "sliding" -> return [(i, i + k - 1) | i <- [0 .. n - k]]
    "fixed"   -> return [(i, i + k - 1) | i <- [0, stride .. n - k]]
    "random"  -> let rnd = mkStdGen seed in go 0 (randomRs (0,2) rnd) (randomRs (0,k-1) rnd) []
      where
        go left (dl:ds) (dr:rs) ws =
          let l = left + dl; r = l + dr
          in if r >= n then ws else go l ds rs (ws ++ [(l,r)])
        go _ _ _ ws = ws
    "file"    -> case mfile of
                   Just f -> readFile f >>= return . map (\line -> let [l,r] = map read (words $ map (\c -> if c == ',' then ' ' else c) line) in (l,r)) . lines
                   Nothing -> die "Need -file argument for mode=file"
    _         -> die $ "Unknown mode " ++ mode

ops :: String -> (Int -> Int -> Int)
ops "sum"     = (+)
ops "product" = (*)
ops "max"     = max
ops "min"     = min
ops op        = error $ "Unknown operator: " ++ op

main :: IO ()
main = do
    args <- getArgs
    let opt s def = maybe def id $ lookup s $ pairs args
        pairs (a:v:rest) = (a,v):pairs rest
        pairs _ = []
        n     = read $ opt "-n" "10000000"
        k     = read $ opt "-k" "1000"
        opStr =      opt "-op" "sum"
        seed  = read $ opt "-seed" "42"
        stride= read $ opt "-stride" "1"
        mode  =      opt "-mode" "sliding"
        runs  = read $ opt "-runs" "5"
        file  = opt "-file" ""
        mfile = if file == "" then Nothing else Just file

    putStrLn $ "n=" ++ show n ++ " k="++show k++" seed="++show seed++" op="++opStr++" mode="++mode
    let operation = ops opStr
    mapM_ (\run -> do
        let thisSeed = seed + 2 * run
            elems = take n $ randomRs (minBound::Int, maxBound::Int) (mkStdGen thisSeed)
        wins <- genWindows mode n k stride (seed + 2 * run + 1) mfile

        putStr $ "run=" ++ show run ++ "\twindows="++show (length wins) ++ "\t"
        t1 <- getPOSIXTime
        let results = slidingWindow operation elems wins
        t2 <- getPOSIXTime
        printf "results=%d\taggregation time=%.6fs\n" (length results) (realToFrac (t2-t1) :: Double)
      ) [1..runs]

