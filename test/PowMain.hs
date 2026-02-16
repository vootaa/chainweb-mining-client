{-# LANGUAGE OverloadedStrings #-}

module Main
( main
) where

import Test.Syd

import qualified Test.PowHash
import qualified Test.PowIntegration

main :: IO ()
main = sydTest tests

tests :: Spec
tests =
    describe "Test.PowHash" Test.PowHash.tests
    >> describe "Test.PowIntegration" Test.PowIntegration.tests
