import System.Environment (getArgs)
import System.Random (mkStdGen, randomRs)
import System.Exit (die)
import Data.List (foldl1')
import Data.Time.Clock.POSIX (getPOSIXTime)
import Sliding (slidingWindow)
import Text.Printf (printf)
import System.IO (withFile, IOMode(..), hPutStrLn, stdout)

-- Window generation matching Go/Python
-- mode: fixed, random, file
-- s: slide/stride
-- file: file path for window specs (for mode=file or -out)
genWindows :: String -> Int -> Int -> Int -> Int -> Maybe FilePath -> IO [(Int,Int)]
genWindows mode n k s seed mfile = case mode of
    "fixed"   -> return [(i, i + k - 1) | i <- [0, s .. n - k]]
    "random"  -> let rnd = mkStdGen seed in go (randomRs (0,s) rnd) (randomRs (0,s) rnd) (0, k) []
      where
        go (dl:ds) (dr:rs) (left, right) ws =
          if right >= n then ws
          else let ws' = ws ++ [(left, right)]
                   left' = left + dl
                   right' = right + dr
                   right'' = if right' < left' then left' + dr else right'
               in go ds rs (left', right'') ws'
        go _ _ _ ws = ws
    "file"    -> case mfile of
                   Just f -> do
                     content <- readFile f
                     return $ map (\line -> let [l,r] = map read (words $ map (\c -> if c == ',' then ' ' else c) line) in (l,r)) $ lines content
                   Nothing -> die "Need -file argument for mode=file"
    _         -> die $ "Unknown mode " ++ mode

ops :: String -> (Int -> Int -> Int)
ops "sum"     = (+)
ops "product" = (*)
ops "max"     = max
ops "min"     = min
ops op        = error $ "Unknown operator: " ++ op

-- Naive O(nw) aggregation
aggregateNaive :: (Int -> Int -> Int) -> [Int] -> [(Int,Int)] -> [Int]
aggregateNaive op xs wins = [foldl1' op (take (r-l+1) (drop l xs)) | (l,r) <- wins, l >= 0, r < length xs, l <= r]

-- Dump windows to file/stdout
writeWindows :: Maybe FilePath -> [(Int,Int)] -> IO ()
writeWindows Nothing wins = mapM_ (\(l,r) -> putStrLn (show l ++ "," ++ show r)) wins
writeWindows (Just f) wins = withFile f WriteMode $ \h -> mapM_ (\(l,r) -> hPutStrLn h (show l ++ "," ++ show r)) wins

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
        s     = read $ opt "-s" "1"
        mode  =      opt "-mode" "fixed"
        runs  = read $ opt "-runs" "5"
        file  = opt "-file" ""
        mfile = if file == "" then Nothing else Just file
        naive = elem "-naive" args
        out   = elem "-out" args

    -- Validation
    if n < 1 || k < 1 || s < 1 || runs < 0 || not (mode `elem` ["fixed","random","file"]) || not (opStr `elem` ["sum","product","max","min"]) then
      die "Error: invalid value(s)"
    else return ()

    -- Dump windows and exit
    if out then do
      wins <- genWindows mode n k s seed mfile
      writeWindows mfile wins
      case mfile of
        Just f -> putStrLn $ "Dumped " ++ show (length wins) ++ " windows to " ++ f
        Nothing -> return ()
      return ()
    else do
      putStrLn $ "mode=" ++ mode ++ " n=" ++ show n ++ " k=" ++ show k ++ " s=" ++ show s ++ " seed=" ++ show seed ++ " op=" ++ opStr ++ " naive=" ++ show naive ++ "\n"
      let operation = ops opStr
      mapM_ (\run -> do
        let thisSeed = seed + 2 * run
            elems = take n $ randomRs (minBound::Int, maxBound::Int) (mkStdGen thisSeed)
        wins <- genWindows mode n k s (seed + 2 * run + 1) mfile
        putStr $ "run=" ++ show run ++ "\twindows=" ++ show (length wins) ++ "\t"
        t1 <- getPOSIXTime
        let results = if naive then aggregateNaive operation elems wins else slidingWindow operation elems wins
        t2 <- getPOSIXTime
        printf "results=%d\taggregation time=%.6fs\n" (length results) (realToFrac (t2-t1) :: Double)
        ) [1..runs]

