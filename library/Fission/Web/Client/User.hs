module Fission.Web.Client.User
  ( register
  , verify
  , updateDID
  , getEmail
  ) where

import Fission.Prelude

import Servant hiding (addHeader)
import Servant.Client

import qualified Fission.User.Registration.Types as User
import qualified Fission.User.Username.Types     as User
import qualified Fission.User.Email.Types        as User
import qualified Fission.User.DID.Types        as User

import           Fission.Web.Client
import qualified Fission.Web.User       as User
import           Fission.Web.Routes (UserPrefix)

register  :: User.Registration -> ClientM ()
register = registerClient <| Proxy @(UserPrefix :> User.RegisterRoute)

verify    :: ClientM User.Username
verify = sigClient' <| Proxy @(UserPrefix :> User.VerifyRoute)

updateDID :: BasicAuthData -> User.DID -> ClientM User.DID
updateDID = basicClient <| Proxy @(UserPrefix :> User.UpdateDIDRoute)

getEmail  :: User.Username -> ClientM User.Email
getEmail = client <| Proxy @(UserPrefix :> User.EmailRoute)
