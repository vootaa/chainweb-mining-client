{-# LANGUAGE OverloadedStrings #-}

module Test.PowHash
( tests
) where

import Crypto.Hash
import Crypto.Hash.Algorithms (Blake2b_256)

import Data.Bits
import qualified Data.ByteString as B
import qualified Data.ByteString.Short as BS
import Data.Word

import Test.Syd

import Target
import Worker
import WorkerUtils

tests :: Spec
tests = do
    describe "powDomainPrefix" $ do
        it "uses mono prefix for version code 0x10" $ do
            let w = mkWorkWithVersionCode 0x00000010
            powDomainPrefix w `shouldBe` "Vootaa-POW-PS1|mono"

        it "uses triad prefix for version code 0x11" $ do
            let w = mkWorkWithVersionCode 0x00000011
            powDomainPrefix w `shouldBe` "Vootaa-POW-PS1|triad"

        it "uses icosa prefix for version code 0x12" $ do
            let w = mkWorkWithVersionCode 0x00000012
            powDomainPrefix w `shouldBe` "Vootaa-POW-PS1|icosa"

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
