module Main where

foreign import status :: Int

foreign import templatePath :: String

main :: Int
main = status
