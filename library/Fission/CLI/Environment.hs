-- | Reading and writing local user config values
module Fission.CLI.Environment
  ( init
  , get
  , decode
  , find
  , write
  , writePassword
  , cachePath
  , couldNotRead
  , removeConfigFile
  , getOrRetrievePeer
  ) where

import           RIO           hiding (set)
import           RIO.Directory
import           RIO.File
import           RIO.FilePath
import           Servant.API

import qualified System.Console.ANSI as ANSI

import           Data.Has
import qualified Data.Yaml as YAML
import           Data.List.NonEmpty as NonEmpty hiding (init)

import           Fission.Internal.Constraint

import           Fission.Web.Client.Peers as Peers
import qualified Fission.Web.Client.Types as Client

import qualified Fission.User.Password.Types as User

import qualified Fission.CLI.Display.Success as CLI.Success
import qualified Fission.CLI.Display.Error   as CLI.Error

import           Fission.CLI.Environment.Types
import qualified Fission.CLI.Environment.Error as Error

import           Fission.Internal.Orphanage.BasicAuthData ()
import qualified Fission.Internal.UTF8 as UTF8

import qualified Fission.IPFS.Peer  as IPFS.Peer
import qualified Fission.IPFS.Types as IPFS

buildEnv :: MonadIO m => m PartialEnv
buildEnv = do
  env <- getCurrentDirectory >>= recurseEnv
  getUsername env

recurseEnv :: MonadIO m => FilePath -> m PartialEnv
recurseEnv "/" = decodePartial $ "/.fission.yaml"
recurseEnv path = do
  parent <- recurseEnv $ takeDirectory path
  curr <- decodePartial $ path </> ".fission.yaml"
  return $ parent <> curr

-- | Retrieve auth from the user's system
decodePartial :: MonadIO m => FilePath -> m PartialEnv
decodePartial path = liftIO $ YAML.decodeFileEither path >>= \case
  Left _ -> return $ mempty PartialEnv
  Right env -> return env

-- | Initialize the Config file
init :: MonadRIO cfg m
      => HasLogFunc        cfg
      => Has Client.Runner cfg
      => BasicAuthData
      -> m ()
init auth = initAt auth =<< cachePath

initAt :: MonadRIO cfg m
      => HasLogFunc        cfg
      => Has Client.Runner cfg
      => BasicAuthData
      -> FilePath
      -> m ()
initAt auth path = do
  logDebug "Initializing config file"

  Peers.getPeers >>= \case
    Left err ->
      CLI.Error.put err "Peer retrieval failed"

    Right peers -> do
      liftIO $ write auth peers path
      CLI.Success.putOk "Logged in"

-- | Retrieve auth from the user's system
get :: MonadIO m => m (Either SomeException Environment)
get = find >>= \case
  Just path -> mapLeft toException <$> decode path
  Nothing -> return . Left $ toException Error.EnvNotFound

-- | Retrieve auth from the user's system
decode :: MonadIO m => FilePath -> m (Either YAML.ParseException Environment)
decode path = liftIO . YAML.decodeFileEither $ path

-- | Locate auth on the user's system
find :: MonadIO m => m (Maybe FilePath)
find = do
  currDir <- getCurrentDirectory
  findRecurse currDir

findRecurse :: MonadIO m => FilePath -> m (Maybe FilePath)
findRecurse path = do
  let filepath = path </> ".fission.yaml"
  exists <- doesFileExist filepath
  if exists
    then return $ Just filepath
    else case path of
      "/" -> return Nothing
      _   -> findRecurse $ takeDirectory path

write :: MonadUnliftIO m => BasicAuthData -> [IPFS.Peer] -> FilePath -> m ()
write auth peers path = do
  let configFileContent = Environment
                            { peers = Just (NonEmpty.fromList peers)
                            , userAuth = auth
                            }
  writeBinaryFileDurable path $ YAML.encode $ configFileContent

-- | Absolute path of the auth cache on disk
cachePath :: MonadIO m => m FilePath
cachePath = do
  home <- getHomeDirectory
  return $ home </> ".fission.yaml"

writePassword :: MonadRIO cfg m
      => HasLogFunc        cfg
      => Has Client.Runner cfg
      => User.Password
      -> m (Either SomeException Bool)
writePassword (User.Password newPass) =
  find >>= \case
    Nothing -> return . Left $ toException Error.EnvNotFound 
    Just path -> decode path >>= \case
      Left err -> return . Left $ toException err
      Right env -> do
        let auth = BasicAuthData
                    (basicAuthUsername . userAuth $ env)
                    (encodeUtf8 $ fromMaybe "" newPass)
        initAt auth path
        return $ Right True

-- | Create a could not read message for the terminal
couldNotRead :: MonadIO m => m ()
couldNotRead = do
  liftIO $ ANSI.setSGR [ANSI.SetColor ANSI.Foreground ANSI.Vivid ANSI.Red]
  UTF8.putText "🚫 Unable to read credentials. Try logging in with "

  liftIO $ ANSI.setSGR [ANSI.SetColor ANSI.Foreground ANSI.Vivid ANSI.Blue]
  UTF8.putText "fission-cli login\n"

  liftIO $ ANSI.setSGR [ANSI.Reset]

-- | Removes the users config file
removeConfigFile :: MonadUnliftIO m => m (Either IOException ())
removeConfigFile = do
  path <- cachePath
  try $ removeFile path

-- | Retrieves a Fission Peer from local config
--   If not found we retrive from the network and store
getOrRetrievePeer :: MonadRIO          cfg m
                  => MonadUnliftIO         m
                  => HasLogFunc        cfg
                  => Has Client.Runner cfg
                  => Environment
                  -> m IPFS.Peer
getOrRetrievePeer config =
  case peers config of
    Just prs -> do
      logDebug "Retrieved Peer from .fission.yaml"
      return $ head prs

    Nothing ->
      Peers.getPeers >>= \case
        Left err -> do
          logError $ displayShow err
          logDebug "Unable to retrieve peers from the network, using default address"
          return $ IPFS.Peer.fission

        Right peers -> do
          logDebug "Retrieved Peer from API"
          let auth = userAuth config
          write auth peers =<< cachePath
          return $ head $ NonEmpty.fromList peers
