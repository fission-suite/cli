-- | Register command
module Fission.CLI.Command.Register (command, register) where
import qualified Data.ByteString.UTF8 as UTF8

import           Fission.Prelude
import           RIO.ByteString

import qualified Data.ByteString.Char8 as BS
import qualified Data.Text as T

import           Options.Applicative.Simple hiding (command)
import           Servant
import           System.Console.Haskeline

import qualified Fission.Config as Config

import qualified Fission.Web.Client.User  as User.Client
import qualified Fission.Web.Client.Types as Client

import qualified Fission.User.Registration.Types as User

import qualified Fission.CLI.Environment               as Env
import           Fission.CLI.Environment.Partial.Types as Env
import qualified Fission.CLI.Environment.Partial       as Env.Partial

import           Fission.CLI.Config.Types

import           Fission.CLI.Command.Register.Types as Register
import qualified Fission.CLI.Display.Cursor  as Cursor
import qualified Fission.CLI.Display.Success as CLI.Success
import qualified Fission.CLI.Display.Error   as CLI.Error
import qualified Fission.CLI.Display.Wait    as CLI.Wait

-- | The command to attach to the CLI tree
command :: MonadUnliftIO m
        => HasLogFunc        cfg
        => Has Client.Runner cfg
        => cfg
        -> CommandM (m ())
command cfg =
  addCommand
    "register"
    "Register for Fission and login"
    (\options -> void <| runRIO cfg <| register options)
    parseOptions

-- | Register and login (i.e. save credentials to disk)
register ::
  ( MonadReader       cfg m
  , MonadIO               m
  , MonadUnliftIO         m
  , MonadLogger           m
  , Has Client.Runner cfg
  )
  => Register.Options
  -> m ()
register Register.Options {..} = do
  envPath <- Env.getPath local_auth
  env <- Env.Partial.decode envPath
  case maybeUserAuth env of
    Nothing -> register' local_auth
    Just _ ->
      CLI.Success.putOk <| mconcat
        [ "Already registered. Remove your credentials at "
        ,  textShow envPath
        , " if you want to re-register"]

-- | Prompt a user for a value and do not accept an empty value
getRequired ::
  ( MonadReader       cfg m
  , MonadIO               m
  , MonadLogger           m
  )
  => ByteString
  -> m ByteString
getRequired fieldName = do
  putStr (fieldName <> ": ")
  fieldValue <- getLine
  if BS.length fieldValue <= 0 then do
    putStr (fieldName <> " is required\n ")
    getRequired fieldName
  else
    return fieldValue

-- | Prompt a user for a secret and do not accept an empty value
getRequiredSecret ::
  ( MonadReader       cfg m
  , MonadIO               m
  , MonadLogger           m
  )
  => ByteString
  -> m ByteString
getRequiredSecret fieldName = do
  let label = UTF8.toString (fieldName <> ": ")
  liftIO (runInputT defaultSettings <| getPassword (Just '•') label) >>= \case
    Nothing -> do
      logError <| show "Unable to read password"
      putStr (fieldName <> " is required\n ")
      getRequiredSecret fieldName

    Just password -> do
      let bsPassword = BS.pack password
      if BS.length bsPassword <= 0 then do
        putStr (fieldName <> " is required\n ")
        getRequiredSecret fieldName
      else
        return bsPassword

register' ::
  ( MonadReader       cfg m
  , MonadIO               m
  , MonadUnliftIO         m
  , MonadLogger           m
  , Has Client.Runner cfg
  )
  => Bool
  -> m ()
register' local_auth = do
  logDebug <| show "Starting registration sequence"

  username <- getRequired "Username"
  password <- getRequiredSecret "Password"
  rawEmail <- getRequired "Email"

  logDebug <| show "Attempting registration"
  Client.Runner runner <- Config.get

  registerResult <- Cursor.withHidden
                  . liftIO
                  . CLI.Wait.waitFor "Registering..."
                  . runner
                  . User.Client.register
                  <| User.Registration
                      { username = decodeUtf8Lenient username
                      , password = decodeUtf8Lenient password
                      , email    = decodeUtf8Lenient rawEmail
                      }

  case registerResult of
    Left  err ->
      CLI.Error.put err "Authorization failed"

    Right _ok -> do
      logDebug <| show "Register Successful"

      let auth = BasicAuthData username password
      envPath <- Env.getPath local_auth

      if local_auth
      then Env.Partial.writeMerge envPath
        <| (mempty Env.Partial) { maybeUserAuth = Just auth }
      else Env.init auth

      CLI.Success.putOk <| "Registered & logged in. Your credentials are in " <> textShow envPath

parseOptions :: Parser Register.Options
parseOptions = do
  local_auth <- switch <| mconcat
    [ long "local"
    , help "Register at project root (as opposed to global at user home)"
    ]

  return Register.Options {..}
