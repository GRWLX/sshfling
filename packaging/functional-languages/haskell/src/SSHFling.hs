module SSHFling
  ( run
  , runtimePath
  , templateDirectory
  ) where

import Control.Exception (IOException, catch)
import Paths_sshfling (getDataFileName)
import System.Directory (doesFileExist, getPermissions, setOwnerExecutable, setPermissions)
import System.Environment (getEnvironment, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.Process (CreateProcess (env), createProcess, proc, waitForProcess)

configuredOr :: String -> IO FilePath -> IO FilePath
configuredOr name fallback = do
  configured <- lookupEnv name
  case configured of
    Just value | not (null value) -> pure value
    _ -> fallback

runtimePath :: IO FilePath
runtimePath = configuredOr "SSHFLING_RUNTIME" (getDataFileName "runtime/sshfling.py")

templateDirectory :: IO FilePath
templateDirectory =
  configuredOr "SSHFLING_TEMPLATE_DIR" (getDataFileName "runtime/templates")

replaceEnvironment :: String -> String -> [(String, String)] -> [(String, String)]
replaceEnvironment name value variables =
  (name, value) : filter ((/= name) . fst) variables

executableTemplates :: [FilePath]
executableTemplates =
  [ "native/sshfling-linux-account"
  , "native/sshfling-unix-identity"
  , "production/sshfling-login-shell"
  , "production/sshfling-session"
  , "scripts/create-network.sh"
  , "scripts/generate-ssh-key.sh"
  , "scripts/install-local.sh"
  , "scripts/uninstall-local.sh"
  , "ssh-client/entrypoint.sh"
  , "ssh-server/entrypoint.sh"
  , "ssh-server/limited-session.sh"
  ]

markExecutable :: FilePath -> IO ()
markExecutable path = do
  permissions <- getPermissions path
  setPermissions path (setOwnerExecutable True permissions)

prepareResources :: FilePath -> FilePath -> IO ()
prepareResources runtime templates =
  mapM_ markExecutable (runtime : map (templates </>) executableTemplates)

run :: [String] -> IO Int
run arguments = catch launch missingExecutable
  where
    launch = do
      python <- configuredOr "SSHFLING_PYTHON" (pure "python3")
      runtime <- runtimePath
      runtimeExists <- doesFileExist runtime
      if not runtimeExists
        then pure 127
        else do
          templates <- templateDirectory
          prepareResources runtime templates
          inherited <- getEnvironment
          let childEnvironment =
                replaceEnvironment "PYTHONUNBUFFERED" "1"
                  (replaceEnvironment "SSHFLING_TEMPLATE_DIR" templates inherited)
          (_, _, _, handle) <-
            createProcess (proc python (runtime : arguments)) {env = Just childEnvironment}
          status <- waitForProcess handle
          pure $ case status of
            ExitSuccess -> 0
            ExitFailure code -> code
    missingExecutable :: IOException -> IO Int
    missingExecutable _ = pure 127
