{- Data/Singletons/Promote/Monad.hs

(c) Richard Eisenberg 2014
rae@cs.brynmawr.edu

This file defines the PrM monad and its operations, for use during promotion.

The PrM monad allows reading from a PrEnv environment and writing to a list
of DDec, and is wrapped around a Q.
-}

{-# LANGUAGE GeneralizedNewtypeDeriving, StandaloneDeriving,
             FlexibleContexts, TypeFamilies, KindSignatures #-}

module Data.Singletons.Promote.Monad (
  PrM, promoteM, promoteM_, promoteMDecs, VarPromotions,
  allLocals, emitDecs, emitDecsM,
  lambdaBind, LetBind, letBind, lookupVarE, forallBind, allBoundKindVars
  ) where

import Control.Monad.Reader
import Control.Monad.Writer
import qualified Data.Map.Strict as Map
import Data.Map.Strict ( Map )
import qualified Data.Set as Set
import Data.Set ( Set )
import Language.Haskell.TH.Syntax hiding ( lift )
import Language.Haskell.TH.Desugar
import Data.Singletons.Names
import Data.Singletons.Syntax
import Control.Monad.Fail ( MonadFail )

type LetExpansions = Map Name DType  -- from **term-level** name

-- environment during promotion
data PrEnv =
  PrEnv { pr_lambda_bound :: Map Name Name
        , pr_let_bound    :: LetExpansions
        , pr_forall_bound :: Set Name -- See Note [Explicitly quantifying kinds variables]
        , pr_local_decls  :: [Dec]
        }

emptyPrEnv :: PrEnv
emptyPrEnv = PrEnv { pr_lambda_bound = Map.empty
                   , pr_let_bound    = Map.empty
                   , pr_forall_bound = Set.empty
                   , pr_local_decls  = [] }

-- the promotion monad
newtype PrM a = PrM (ReaderT PrEnv (WriterT [DDec] Q) a)
  deriving ( Functor, Applicative, Monad, Quasi
           , MonadReader PrEnv, MonadWriter [DDec]
           , MonadFail, MonadIO )

instance DsMonad PrM where
  localDeclarations = asks pr_local_decls

-- return *type-level* names
allLocals :: MonadReader PrEnv m => m [Name]
allLocals = do
  lambdas <- asks (Map.toList . pr_lambda_bound)
  lets    <- asks pr_let_bound
    -- filter out shadowed variables!
  return [ typeName
         | (termName, typeName) <- lambdas
         , case Map.lookup termName lets of
             Just (DVarT typeName') | typeName' == typeName -> True
             _                                              -> False ]

emitDecs :: MonadWriter [DDec] m => [DDec] -> m ()
emitDecs = tell

emitDecsM :: MonadWriter [DDec] m => m [DDec] -> m ()
emitDecsM action = do
  decs <- action
  emitDecs decs

-- when lambda-binding variables, we still need to add the variables
-- to the let-expansion, because of shadowing. ugh.
lambdaBind :: VarPromotions -> PrM a -> PrM a
lambdaBind binds = local add_binds
  where add_binds env@(PrEnv { pr_lambda_bound = lambdas
                             , pr_let_bound    = lets }) =
          let new_lets = Map.fromList [ (tmN, DVarT tyN) | (tmN, tyN) <- binds ] in
          env { pr_lambda_bound = Map.union (Map.fromList binds) lambdas
              , pr_let_bound    = Map.union new_lets lets }

type LetBind = (Name, DType)
letBind :: [LetBind] -> PrM a -> PrM a
letBind binds = local add_binds
  where add_binds env@(PrEnv { pr_let_bound = lets }) =
          env { pr_let_bound = Map.union (Map.fromList binds) lets }

lookupVarE :: Name -> PrM DType
lookupVarE n = do
  lets <- asks pr_let_bound
  case Map.lookup n lets of
    Just ty -> return ty
    Nothing -> return $ promoteValRhs n

-- Add to the set of bound kind variables currently in scope.
-- See Note [Explicitly binding kind variables]
forallBind :: Set Name -> PrM a -> PrM a
forallBind kvs1 =
  local (\env@(PrEnv { pr_forall_bound = kvs2 }) ->
    env { pr_forall_bound = kvs1 `Set.union` kvs2 })

-- Look up the set of bound kind variables currently in scope.
-- See Note [Explicitly binding kind variables]
allBoundKindVars :: PrM (Set Name)
allBoundKindVars = asks pr_forall_bound

promoteM :: DsMonad q => [Dec] -> PrM a -> q (a, [DDec])
promoteM locals (PrM rdr) = do
  other_locals <- localDeclarations
  let wr = runReaderT rdr (emptyPrEnv { pr_local_decls = other_locals ++ locals })
      q  = runWriterT wr
  runQ q

promoteM_ :: DsMonad q => [Dec] -> PrM () -> q [DDec]
promoteM_ locals thing = do
  ((), decs) <- promoteM locals thing
  return decs

-- promoteM specialized to [DDec]
promoteMDecs :: DsMonad q => [Dec] -> PrM [DDec] -> q [DDec]
promoteMDecs locals thing = do
  (decs1, decs2) <- promoteM locals thing
  return $ decs1 ++ decs2

{-
Note [Explicitly binding kind variables]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
We want to ensure that when we single type signatures for functions, we should
explicitly quantify every kind variable bound by a forall. For example, if we
were to single the identity function:

  identity :: forall a. a -> a
  identity x = x

We want the final result to be:

  sIdentity :: forall a (x :: a). Sing x -> Sing (Identity x)
  sIdentity sX = sX

Accomplishing this takes a bit of care during promotion. When promoting a
function, we determine what set of kind variables are currently bound at that
point and store them in an ALetDecEnv (as lde_bound_kvs), which in turn is
singled. Then, during singling, we extract every kind variable in a singled
type signature, subtract the lde_bound_kvs, and explicitly bind the variables
that remain.

For a top-level function like identity, lde_bound_kvs is the empty set. But
consider this more complicated example:

  f :: forall a. a -> a
  f = g
    where
      g :: a -> a
      g x = x

When singling, we would eventually end up in this spot:

  sF :: forall a (x :: a). Sing a -> Sing (F a)
  sF = sG
    where
      sG :: _
      sG x = x

We must make sure /not/ to fill in the following type for _:

  sF :: forall a (x :: a). Sing a -> Sing (F a)
  sF = sG
    where
      sG :: forall a (y :: a). Sing a -> Sing (G a)
      sG x = x

This would be incorrect, as the `a` bound by sF /must/ be the same one used in
sG, as per the scoping of the original `f` function. Thus, we ensure that the
bound variables from `f` are put into lde_bound_kvs when promoting `g` so
that we subtract out `a` and are left with the correct result:

  sF :: forall a (x :: a). Sing a -> Sing (F a)
  sF = sG
    where
      sG :: forall (y :: a). Sing a -> Sing (G a)
      sG x = x
-}
