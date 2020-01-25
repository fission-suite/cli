module Fission.Web.Client.DNS (update) where

import           Fission.Prelude

import           Servant.Client

import           Network.IPFS.CID.Types
import qualified Fission.Web.Routes           as Routes

import           Fission.Web.Client

import qualified Fission.URL.DomainName.Types as URL

update :: CID -> ClientM URL.DomainName
update = sigClient <| Proxy @Routes.DNSRoute
