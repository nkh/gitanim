module Main where

import Data.List (sort)

factorial :: Int -> Int
factorial 0 = 1
factorial n = n * factorial (n - 1)

fibonacci :: Int -> Int
fibonacci 0 = 0
fibonacci 1 = 1
fibonacci n = fibonacci (n - 1) + fibonacci (n - 2)

main :: IO ()
main = do
  putStrLn $ "Factorial of 5: " ++ show (factorial 5)
  putStrLn $ "Fibonacci of 10: " ++ show (fibonacci 10)
  putStrLn $ "Sorted: " ++ show (sort [3, 1, 4, 1, 5, 9, 2, 6])
