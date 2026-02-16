{-# LANGUAGE OverloadedStrings #-}

module Test.PowHash
( tests
) where

import Control.Exception (ErrorCall, evaluate, try)

import Crypto.Hash
import Crypto.Hash.Algorithms (Blake2b_256)

import Data.Bits
import qualified Data.ByteString as B
import qualified Data.ByteString.Short as BS
import Data.Either (isLeft)
import Data.List (isInfixOf)
import Data.Word

import Test.Syd

import Target
import Worker
import WorkerUtils

tests :: Spec
tests = do
    describe "powDomainPrefix" $ do
        it "uses recap-development prefix for version code 0x01" $ do
            let w = mkWorkWithVersionCode 0x00000001
            powDomainPrefix w `shouldBe` "Vootaa-POW-PS1|recap-development"

        it "uses development prefix for version code 0x02" $ do
            let w = mkWorkWithVersionCode 0x00000002
            powDomainPrefix w `shouldBe` "Vootaa-POW-PS1|development"

        it "uses mainnet01 prefix for version code 0x05" $ do
            let w = mkWorkWithVersionCode 0x00000005
            powDomainPrefix w `shouldBe` "Vootaa-POW-PS1|mainnet01"

        it "uses testnet04 prefix for version code 0x07" $ do
            let w = mkWorkWithVersionCode 0x00000007
            powDomainPrefix w `shouldBe` "Vootaa-POW-PS1|testnet04"

        it "uses mono prefix for version code 0x10" $ do
            let w = mkWorkWithVersionCode 0x00000010
            powDomainPrefix w `shouldBe` "Vootaa-POW-PS1|mono"

        it "uses triad prefix for version code 0x11" $ do
            let w = mkWorkWithVersionCode 0x00000011
            powDomainPrefix w `shouldBe` "Vootaa-POW-PS1|triad"

        it "uses icosa prefix for version code 0x12" $ do
            let w = mkWorkWithVersionCode 0x00000012
            powDomainPrefix w `shouldBe` "Vootaa-POW-PS1|icosa"

        it "throws for unsupported version code" $ do
            let w = mkWorkWithVersionCode 0x000000ff
            r <- (try (evaluate (powDomainPrefix w)) :: IO (Either ErrorCall B.ByteString))
            r `shouldSatisfy` isLeft

        it "reports unsupported version code in error message" $ do
            let w = mkWorkWithVersionCode 0x000000ff
            r <- (try (evaluate (powDomainPrefix w)) :: IO (Either ErrorCall B.ByteString))
            case r of
                Left e -> show e `shouldSatisfy` isInfixOf "Unsupported ChainwebVersionCode"
                Right _ -> expectationFailure "expected powDomainPrefix to throw"

    describe "powHash" $ do
        it "matches Blake2b_256(prefix <> workBytes)" $ do
            let w@(Work bytes) = mkWorkWithVersionCode 0x00000010
                expected :: Digest Blake2b_256
                expected = hash (powDomainPrefix w <> BS.fromShort bytes)
            powHash w `shouldBe` expected

        it "changes when version domain changes" $ do
            let monoWork = mkWorkWithVersionCode 0x00000010
                triadWork = mkWorkWithVersionCode 0x00000011
            powHash monoWork `shouldNotBe` powHash triadWork

        it "is deterministic for identical work" $ do
            let w = mkWorkWithVersionCode 0x00000012
            powHash w `shouldBe` powHash w

    describe "checkTarget" $ do
        it "accepts target derived from the same pow hash" $ do
            let w = mkWorkWithVersionCode 0x00000012
            wordsForHash <- powHashToTargetWords (powHash w)
            checkTarget (targetFromWords wordsForHash) w `shouldReturn` True

mkWorkWithVersionCode :: Word32 -> Work
mkWorkWithVersionCode versionCode =
    Work
        . BS.toShort
        . setWord32LeAt 266 versionCode
        $ B.replicate 286 0

setWord32LeAt :: Int -> Word32 -> B.ByteString -> B.ByteString
setWord32LeAt offset value bytes =
    prefix <> leBytes <> suffix
  where
    prefix = B.take offset bytes
    suffix = B.drop (offset + 4) bytes
    leBytes = B.pack
        [ fromIntegral value
        , fromIntegral (value `shiftR` 8)
        , fromIntegral (value `shiftR` 16)
        , fromIntegral (value `shiftR` 24)
        ]
