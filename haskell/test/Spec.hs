import Test.Hspec
import Sliding (slidingWindow)

main :: IO ()
main = hspec $ do
  describe "Sliding.slidingWindow" $ do
    it "computes sum over a sliding window" $ do
      -- Stream:    [1,2,3,4,5]
      -- Windows:   [(0,2), (1,3), (2,4)] → [sum 1-3, sum 2-4, sum 3-5]
      let xs = [1,2,3,4,5]
          ws = [(0,2), (1,3), (2,4)]
          result = slidingWindow (+) xs ws
      result `shouldBe` [6,9,12]

    it "computes product over a sliding window" $ do
      let xs = [2,3,4,5]
          ws = [(0,1), (1,2), (2,3)]
          result = slidingWindow (*) xs ws
      result `shouldBe` [6, 12, 20]

    it "handles a single-element window" $ do
      let xs = [7,8,9]
          ws = [(1,1), (2,2)]
          result = slidingWindow (+) xs ws
      result `shouldBe` [8,9]

    it "returns [] if no windows are specified" $ do
      let xs = [1,2,3]
          ws = []
          result = slidingWindow (+) xs ws
      result `shouldBe` []

    it "supports max operator" $ do
      let xs = [4,1,5,2]
          ws = [(0,2),(2,3)]
          result = slidingWindow max xs ws
      result `shouldBe` [5,5]