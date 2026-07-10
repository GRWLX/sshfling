module Main (main) where

import SSHFling (run)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)

main :: IO ()
main = do
  arguments <- getArgs
  status <- run arguments
  exitWith $ if status == 0 then ExitSuccess else ExitFailure status
