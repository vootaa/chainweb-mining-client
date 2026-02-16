{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Test.PowIntegration
( tests
) where

import Control.Concurrent.Async (mapConcurrently)
import Control.Monad (forM_, replicateM)

import Crypto.Hash.Algorithms (Blake2b_256)

import Data.Bits
import Data.Bytes.Get
import Data.Bytes.Put
import qualified Data.ByteString as B
import qualified Data.ByteString.Short as BS
import Data.Word

import System.LogLevel (LogLevel(..))

import Test.Syd

import Logger
import Target
import Worker
import Worker.POW.CPU
import WorkerUtils

tests :: Spec
tests = do
    describe "work encoding integration" $ do
        it "roundtrips encodeWork/decodeWork" $ do
            let w = mkWorkWithVersionCode 0x00000010
            runGetS decodeWork (runPutS $ encodeWork w) `shouldBe` Right w

    describe "pow pipeline integration" $ do
        it "checkTarget accepts exact pow target for mono/triad/icosa" $ do
            mapM_ checkExactTarget [0x00000010, 0x00000011, 0x00000012]

        it "checkTarget rejects a stricter target than pow hash" $ do
            let w = mkWorkWithVersionCode 0x00000012
            wordsForHash <- powHashToTargetWords (powHash w)
            let exactTarget = targetFromWords wordsForHash
            case exactTarget of
                Target n
                    | n > 0 -> checkTarget (Target (n - 1)) w `shouldReturn` False
                    | otherwise -> expectationFailure "unexpected zero pow hash target"

        it "injectNonce changes hash but keeps domain prefix" $ do
            let w = mkWorkWithVersionCode 0x00000010
            w' <- injectNonce (Nonce 1) w
            powDomainPrefix w' `shouldBe` powDomainPrefix w
            powHash w' `shouldNotBe` powHash w

        it "incrementTimeMicros changes hash but keeps domain prefix" $ do
            let w = mkWorkWithVersionCode 0x00000011
                w' = incrementTimeMicros 1 w
            powDomainPrefix w' `shouldBe` powDomainPrefix w
            powHash w' `shouldNotBe` powHash w

        it "injectNonce and incrementTimeMicros are composable" $ do
            let w = mkWorkWithVersionCode 0x00000012
            w1 <- injectNonce (Nonce 42) w
            let w2 = incrementTimeMicros 10 w1
            powDomainPrefix w2 `shouldBe` powDomainPrefix w
            powHash w2 `shouldNotBe` powHash w

    describe "cpu worker integration" $ do
        it "cpuWorker writes nonce into solved work and preserves version domain" $
            withTestLogger $ \logger -> do
                let startNonce = Nonce 0x1122334455667788
                    startWork = mkWorkWithVersionCode 0x00000010
                solved <- cpuWorker @Blake2b_256 logger startNonce maxTarget (ChainId 0) startWork
                nonceFromWork solved `shouldBe` startNonce
                versionCodeFromWork solved `shouldBe` 0x00000010
                powDomainPrefix solved `shouldBe` powDomainPrefix startWork

        it "cpuWorker returns work that satisfies its exact derived target" $
            withTestLogger $ \logger -> do
                let startNonce = Nonce 99
                    startWork = mkWorkWithVersionCode 0x00000012
                solved <- cpuWorker @Blake2b_256 logger startNonce maxTarget (ChainId 0) startWork
                solved `shouldNotBe` startWork
                wordsForHash <- powHashToTargetWords (powHash solved)
                checkTarget (targetFromWords wordsForHash) solved `shouldReturn` True

    describe "cpu worker concurrency and stability" $ do
        it "handles concurrent workers with isolated nonce writes" $
            withTestLogger $ \logger -> do
                let versionCode = 0x00000011
                    job n = do
                        let startNonce = Nonce n
                            startWork = mkWorkWithVersionCode versionCode
                        solved <- cpuWorker @Blake2b_256 logger startNonce maxTarget (ChainId 0) startWork
                        return (startNonce, solved)
                results <- mapConcurrently job [1 .. 32]
                forM_ results $ \(startNonce, solved) -> do
                    nonceFromWork solved `shouldBe` startNonce
                    versionCodeFromWork solved `shouldBe` versionCode
                    checkTarget maxTarget solved `shouldReturn` True

        it "is stable across repeated runs for the same input" $
            withTestLogger $ \logger -> do
                let startNonce = Nonce 424242
                    versionCode = 0x00000012
                    startWork = mkWorkWithVersionCode versionCode
                solvedBatch <- replicateM 20 $ cpuWorker @Blake2b_256 logger startNonce maxTarget (ChainId 0) startWork
                forM_ solvedBatch $ \solved -> do
                    nonceFromWork solved `shouldBe` startNonce
                    versionCodeFromWork solved `shouldBe` versionCode
                    powDomainPrefix solved `shouldBe` powDomainPrefix startWork
                    checkTarget maxTarget solved `shouldReturn` True

        it "handles boundary concurrency (128 workers) with mixed versions" $
            withTestLogger $ \logger -> do
                let versionPool = [0x00000010, 0x00000011, 0x00000012]
                    chooseVersion i = versionPool !! (fromIntegral i `mod` length versionPool)
                    job i = do
                        let startNonce = Nonce (100000 + i)
                            versionCode = chooseVersion i
                            chain = ChainId (fromIntegral (i `mod` 20))
                            startWork = mkWorkWithVersionCode versionCode
                        solved <- cpuWorker @Blake2b_256 logger startNonce maxTarget chain startWork
                        return (startNonce, versionCode, startWork, solved)
                results <- mapConcurrently job [0 .. 127]
                forM_ results $ \(startNonce, versionCode, startWork, solved) -> do
                    nonceFromWork solved `shouldBe` startNonce
                    versionCodeFromWork solved `shouldBe` versionCode
                    powDomainPrefix solved `shouldBe` powDomainPrefix startWork
                    checkTarget maxTarget solved `shouldReturn` True

checkExactTarget :: Word32 -> IO ()
checkExactTarget versionCode = do
    let w = mkWorkWithVersionCode versionCode
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

withTestLogger :: (Logger -> IO a) -> IO a
withTestLogger = withLogger Quiet

nonceFromWork :: Work -> Nonce
nonceFromWork (Work sbs) = Nonce (word64LeAt 278 (BS.fromShort sbs))

versionCodeFromWork :: Work -> Word32
versionCodeFromWork (Work sbs) = word32LeAt 266 (BS.fromShort sbs)

word32LeAt :: Int -> B.ByteString -> Word32
word32LeAt off bs =
    fromIntegral (B.index bs off)
        .|. shiftL (fromIntegral (B.index bs (off + 1))) 8
        .|. shiftL (fromIntegral (B.index bs (off + 2))) 16
        .|. shiftL (fromIntegral (B.index bs (off + 3))) 24

word64LeAt :: Int -> B.ByteString -> Word64
word64LeAt off bs =
    fromIntegral (B.index bs off)
        .|. shiftL (fromIntegral (B.index bs (off + 1))) 8
        .|. shiftL (fromIntegral (B.index bs (off + 2))) 16
        .|. shiftL (fromIntegral (B.index bs (off + 3))) 24
        .|. shiftL (fromIntegral (B.index bs (off + 4))) 32
        .|. shiftL (fromIntegral (B.index bs (off + 5))) 40
        .|. shiftL (fromIntegral (B.index bs (off + 6))) 48
        .|. shiftL (fromIntegral (B.index bs (off + 7))) 56
