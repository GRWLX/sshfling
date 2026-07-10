module Main (main) where

import SSHFling (run)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)

main :: IO ()
main = do
  status <- getArgs >>= run
  exitWith $ if status == 0 then ExitSuccess else ExitFailure status
