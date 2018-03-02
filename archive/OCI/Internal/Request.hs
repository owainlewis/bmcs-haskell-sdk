{-# LANGUAGE DeriveFunctor     #-}
{-# LANGUAGE OverloadedStrings #-}

-------------------------------------------------------------------------
-- |
-- Module      :  Network.Oracle.OCI.Internal.Request
-- License     :  BSD-style (see the file LICENSE)
--
-- Maintainer  :  Owain Lewis <owain@owainlewis.com>
--
-- Add appropriate authentication information to a HTTP request based on
-- https://tools.ietf.org/html/draft-cavage-http-signatures-05
--
-------------------------------------------------------------------------
module Network.Oracle.OCI.Internal.Request
  ( ToRequest(..)
  , transform
  ) where

import qualified Data.ByteString                       as BS
import qualified Data.ByteString.Char8                 as C8
import           Data.CaseInsensitive                  (original)
import           Data.Char                             (toLower)
import           Data.Semigroup                        ((<>))
import           Data.Time
import           Network.HTTP.Client                   (Request (..))
import           Network.HTTP.Simple
import           Network.Oracle.OCI.Credentials        (Credentials, getKeyId,
                                                        getKeyPath)
import qualified Network.Oracle.OCI.Internal.Signature as Signature

class ToRequest a where
  toRequest :: a -> Request
  extractQuery :: a -> [(BS.ByteString, Maybe BS.ByteString)]

-------------------------------------------------------------------------
-- Add HTTP headers
--
-- These methods add the required HTTP headers to a request.
--
-------------------------------------------------------------------------
type HeaderTransformer = Request -> IO Request

-- Add a HTTP date header. It appears this has to be in GMT
--
addDateHeader :: HeaderTransformer
addDateHeader request = do
  now <-
    C8.pack <$> formatTime defaultTimeLocale "%a, %_d %b %Y %H:%M:%S GMT" <$>
    getCurrentTime
  return $ setRequestHeader "date" [now] request

addRequestTargetHeader :: HeaderTransformer
addRequestTargetHeader request =
  pure $ setRequestHeader "(request-target)" [target] request
  where
    rMethod = lowerCaseBS (method request)
    lowerCaseBS = C8.pack . map toLower . C8.unpack
    target = rMethod <> " " <> (path request) <> (queryString request)

addHostHeader :: HeaderTransformer
addHostHeader request = pure $ setRequestHeader "host" [(host request)] request

-- Headers for POST | PUT requests
addContentTypeDefault :: HeaderTransformer
addContentTypeDefault request =
  pure $ setRequestHeader "content-type" ["application/json"] request

-------------------------------------------------------------------------
-- These should already be defined somewhere as part of the http lib.
-- ???
addContentBodyRSA256 request =
  pure $ setRequestHeader "x-content-sha256" [""] request

addContentLengthHeader request =
  pure $ setRequestHeader "content-length" [""] request

-------------------------------------------------------------------------
-- | TODO dispatch on HTTP method adding additional headers if needed
addGenericHeaders :: Request -> IO Request
addGenericHeaders request =
  addDateHeader request >>= addRequestTargetHeader >>= addHostHeader >>=
  addContentTypeDefault

-------------------------------------------------------------------------
computeSignature :: Request -> BS.ByteString
computeSignature request = BS.intercalate "\n" hdrs
  where
    hdrs = map (\(k, v) -> original k <> ": " <> v) (requestHeaders request)

base64EncodedRequestSignature :: Credentials -> Request -> IO BS.ByteString
base64EncodedRequestSignature credentials request = do
  let signature = computeSignature request
  Signature.signBase64 (getKeyPath credentials) signature

zipHeaderPairs :: [(BS.ByteString, BS.ByteString)] -> BS.ByteString
zipHeaderPairs pairs = BS.intercalate "," $ map f pairs
  where
    f = (\(k, v) -> k <> "=\"" <> v <> "\"")

---------------------------------------------------------------------------
-- | Adds the Authorization Signature HTTP header to a request which is
--   formed by signing the HTTP headers
--
addAuthHeader :: Credentials -> Request -> BS.ByteString -> IO Request
addAuthHeader credentials request keyId =
  let headers = (BS.intercalate " ") . map (original . fst) . requestHeaders
  in do signature <- base64EncodedRequestSignature credentials request
        let requestSignature =
              zipHeaderPairs
                [ ("headers", headers request)
                , ("keyId", keyId)
                , ("algorithm", "rsa-sha256")
                , ("signature", signature)
                ]
            finalHeader =
              setRequestHeader
                "authorization"
                ["Signature " <> requestSignature]
                request
        return finalHeader

---------------------------------------------------------------------
-- | Take a normal HTTP request and add the appropritate authentication signature
--   information to it based on credentials provided
--
transform :: Credentials -> Request -> IO Request
transform credentials request =
  let keyId = getKeyId credentials
  in addGenericHeaders request >>= (flip (addAuthHeader credentials) keyId)