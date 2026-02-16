{-# LANGUAGE OverloadedStrings #-}

module Main
( main
) where

import Test.Syd

import qualified Test.PowHash

main :: IO ()
main = sydTest tests

tests :: Spec
tests =
    describe "Test.PowHash" Test.PowHash.tests
