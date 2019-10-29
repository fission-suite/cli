-- | Guards to ensure we have the appropriate peer data available to run an action
module Fission.CLI.Command.Guard.Peers where

import           RIO
import           RIO.Process (ProcessContext, HasProcessContext (..))

import           Data.Has

import           Fission.Internal.Constraint
import           Fission.Internal.Exception

import qualified Fission.Storage.IPFS as IPFS
import qualified Fission.IPFS.Types   as IPFS
import qualified Fission.Web.Client   as Client

import           Fission.CLI.Config.Types
import qualified Fission.Config as Config

ensurePeers
  :: ( MonadRIO          cfg  m
  , HasLogFunc        cfg
  , HasProcessContext cfg
  , Has IPFS.BinPath  cfg
  , Has IPFS.Timeout  cfg
  , Has Client.Runner cfg
  , Has (Maybe (NonEmpty IPFS.Peer)) cfg
  )
  => RIO upCfg a
  -> m a
ensurePeers handler = do
  maybePeers :: Maybe (NonEmpty IPFS.Peer) <- Config.get
  _peers' <- case maybePeers of
              Nothing -> do
                -- get peers from API
                return undefined

              Just peers ->
                return peers

  _logFunc' :: LogFunc <- Config.get
  _processCtx' :: ProcessContext <- Config.get
  _ipfsPath' :: IPFS.BinPath <- Config.get
  _ipfsTimeout' :: IPFS.Timeout <- Config.get
  let newCfg = UpConfig {..}

  localRIO newCfg handler

localRIO :: MonadRIO oldCfg m => newCfg -> RIO newCfg a -> m a
localRIO newCfg action = liftIO $ runRIO newCfg action
