{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE TypeApplications #-}

module Language.JavaScript.Inline.Core.Message where

import Data.Binary
import Data.Binary.Get
import Data.ByteString.Builder
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable
import qualified Data.List.NonEmpty as NE
import Data.String
import Language.JavaScript.Inline.Core.JSVal
import Language.JavaScript.Inline.Core.Utils

data JSCodeSegment
  = Code String
  | BufferLiteral LBS.ByteString
  | StringLiteral String
  | JSONLiteral LBS.ByteString
  | JSValLiteral JSVal
  deriving (Show)

-- | Represents a JavaScript expression. Top-level @await@ is supported.
--
-- Use the 'IsString' instance to convert a 'String' to 'JSCode', and the
-- 'Semigroup' instance for concating 'JSCode'. It's also possible to embed
-- other things into 'JSCode', e.g. a buffer/string literal, JSON value or a
-- 'JSVal'.
newtype JSCode = JSCode
  { unJSCode :: NE.NonEmpty JSCodeSegment
  }
  deriving (Semigroup, Show)

instance IsString JSCode where
  fromString = JSCode . pure . Code

data JSReturnType
  = ReturnNone
  | ReturnBuffer
  | ReturnJSON
  | ReturnJSVal
  deriving (Show)

data MessageHS
  = JSEvalRequest
      { requestId :: Word64,
        code :: JSCode,
        returnType :: JSReturnType
      }
  | JSValFree Word64
  | Close
  deriving (Show)

data MessageJS
  = JSEvalResponse
      { responseId :: Word64,
        responseContent :: Either LBS.ByteString LBS.ByteString
      }
  | FatalError LBS.ByteString
  deriving (Show)

messageHSPut :: MessageHS -> Builder
messageHSPut msg = case msg of
  JSEvalRequest {..} ->
    word8Put 0
      <> word64Put requestId
      <> word64Put (fromIntegral (NE.length (unJSCode code)) :: Word64)
      <> foldMap' codeSegmentPut (unJSCode code)
      <> returnTypePut returnType
    where
      codeSegmentPut (Code s) = word8Put 0 <> lbsPut (stringToLBS s)
      codeSegmentPut (BufferLiteral s) = word8Put 1 <> lbsPut s
      codeSegmentPut (StringLiteral s) = word8Put 2 <> lbsPut (stringToLBS s)
      codeSegmentPut (JSONLiteral s) = word8Put 3 <> lbsPut s
      codeSegmentPut (JSValLiteral v) =
        word8Put 4 <> word64Put (unsafeUseJSVal v)
      returnTypePut ReturnNone = word8Put 0
      returnTypePut ReturnBuffer = word8Put 1
      returnTypePut ReturnJSON = word8Put 2
      returnTypePut ReturnJSVal = word8Put 3
  JSValFree v -> word8Put 1 <> word64Put v
  Close -> word8Put 2
  where
    word8Put = storablePut @Word8
    word64Put = storablePut @Word64
    lbsPut s = storablePut (LBS.length s) <> lazyByteString s

messageJSGet :: Get MessageJS
messageJSGet = do
  t <- getWord8
  case t of
    0 -> do
      _id <- getWord64host
      _tag <- getWord8
      case _tag of
        0 -> do
          _err_buf <- lbsGet
          pure
            JSEvalResponse
              { responseId = _id,
                responseContent = Left _err_buf
              }
        1 -> do
          _result_buf <- lbsGet
          pure
            JSEvalResponse
              { responseId = _id,
                responseContent = Right _result_buf
              }
        _ -> fail $ "messageJSGet: invalid _tag " <> show _tag
    1 -> FatalError <$> lbsGet
    _ -> fail $ "messageJSGet: invalid tag " <> show t
  where
    lbsGet = do
      l <- fromIntegral <$> getWord64host
      getLazyByteString l