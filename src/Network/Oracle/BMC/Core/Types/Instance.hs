{-# LANGUAGE OverloadedStrings #-}
module Network.Oracle.BMC.Core.Types.Instance where

import Data.Aeson
import Control.Monad(mzero)

data Instance = Instance {
    availabilityDomain :: String
  , compartmentId :: String
  , displayName :: String
  , id :: String
  , imageId :: String
} deriving ( Show )

instance FromJSON Instance where
    parseJSON (Object v) =
      Instance <$> v .: "availabilityDomain"
               <*> v .: "compartmentId"
               <*> v .: "displayName"
               <*> v .: "id"
               <*> v .: "imageId"
    parseJSON _ = mzero
