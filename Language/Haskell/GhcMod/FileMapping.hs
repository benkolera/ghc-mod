module Language.Haskell.GhcMod.FileMapping
    ( loadMappedFile
    , loadMappedFiles
    , unloadMappedFile
    , mapFile
    ) where

import Language.Haskell.GhcMod.Types
import Language.Haskell.GhcMod.Monad.Types
import Language.Haskell.GhcMod.Gap
import Language.Haskell.GhcMod.HomeModuleGraph

import System.Directory
import System.FilePath

import Data.Time

import Control.Monad.Trans.Maybe
import GHC

loadMappedFiles :: IOish m => GhcModT m ()
loadMappedFiles = do
  Options {fileMappings} <- options
  mapM_ (uncurry loadMappedFile) fileMappings

loadMappedFile :: IOish m => FilePath -> FileMapping -> GhcModT m ()
loadMappedFile from fm =
  getCanonicalFileName from >>= (`addMMappedFile` fm)

mapFile :: (IOish m, GmState m, GhcMonad m) =>
            HscEnv -> Target -> m Target
mapFile _ (Target tid@(TargetFile filePath _) taoc _) = do
  mapping <- lookupMMappedFile filePath
  mkMappedTarget tid taoc mapping
mapFile env (Target tid@(TargetModule moduleName) taoc _) = do
  mapping <- runMaybeT $ do
    filePath <- MaybeT $ liftIO $ findModulePath env moduleName
    MaybeT $ lookupMMappedFile $ mpPath filePath
  mkMappedTarget tid taoc mapping

mkMappedTarget :: (IOish m, GmState m, GhcMonad m) =>
                  TargetId -> Bool -> Maybe FileMapping -> m Target
mkMappedTarget _ taoc (Just (RedirectedMapping to)) =
  return $ mkTarget (TargetFile to Nothing) taoc Nothing
mkMappedTarget tid taoc (Just (MemoryMapping (Just src))) = do
  sb <- toStringBuffer [src]
  ct <- liftIO getCurrentTime
  return $ mkTarget tid taoc $ Just (sb, ct)
mkMappedTarget tid taoc _ = return $ mkTarget tid taoc Nothing

getCanonicalFileName :: IOish m => FilePath -> GhcModT m FilePath
getCanonicalFileName fn = do
  crdl <- cradle
  let ccfn = cradleCurrentDir crdl </> fn
  liftIO $ canonicalizePath ccfn

unloadMappedFile :: IOish m => FilePath -> GhcModT m ()
unloadMappedFile = (delMMappedFile =<<) . getCanonicalFileName