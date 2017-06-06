{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeInType #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Singletons.Prelude.Show
-- Copyright   :  (C) 2017 Ryan Scott
-- License     :  BSD-style (see LICENSE)
-- Maintainer  :  Richard Eisenberg (rae@cs.brynmawr.edu)
-- Stability   :  experimental
-- Portability :  non-portable
--
-- Defines the SShow singleton version of the Show type class.
--
-----------------------------------------------------------------------------

module Data.Singletons.Prelude.Show (
  PShow(..), SShow(..), SymbolS, SChar, show_,
  (:<>), (%:<>),
  Shows, sShows,
  ShowListWith, sShowListWith,
  ShowChar, sShowChar,
  ShowString, sShowString,
  ShowParen, sShowParen,
  ShowSpace, sShowSpace,
  ShowCommaSpace, sShowCommaSpace,
  AppPrec, sAppPrec,
  AppPrec1, sAppPrec1,

  -- * Defunctionalization symbols
  ShowsPrecSym0, ShowsPrecSym1, ShowsPrecSym2, ShowsPrecSym3,
  Show_Sym0, Show_Sym1,
  ShowListSym0, ShowListSym1, ShowListSym2,
  (:<>$), (:<>$$), (:<>$$$),
  ShowsSym0, ShowsSym1, ShowsSym2,
  ShowListWithSym0, ShowListWithSym1, ShowListWithSym2, ShowListWithSym3,
  ShowCharSym0, ShowCharSym1, ShowCharSym2,
  ShowStringSym0, ShowStringSym1, ShowStringSym2,
  ShowParenSym0, ShowParenSym1, ShowParenSym2,
  ShowSpaceSym0, ShowSpaceSym1,
  ShowCommaSpaceSym0, ShowCommaSpaceSym1,
  AppPrecSym0, AppPrec1Sym0
  ) where

import           Data.Kind (Type)
import           Data.List.NonEmpty (NonEmpty)
import           Data.Monoid ((<>))
import           Data.Singletons.Prelude.Base
import           Data.Singletons.Prelude.Instances
import           Data.Singletons.Prelude.List
import           Data.Singletons.Prelude.Num
import           Data.Singletons.Prelude.Ord
import           Data.Singletons.Prelude.Tuple
import           Data.Singletons.Single
import           Data.Singletons.TH
import           Data.Singletons.TypeLits
import qualified Data.Text as T

import           GHC.TypeLits

import qualified Prelude as P
import           Prelude hiding (Show(..))

import           Unsafe.Coerce (unsafeCoerce)

-- | The promoted analogue of '(<>)' for 'Symbol's. This uses the special
-- 'AppendSymbol' type family from "GHC.TypeLits".
type a :<> b = AppendSymbol a b
infixr 6 :<>

-- | The singleton analogue of '(<>)' for 'Symbol's.
(%:<>) :: Sing a -> Sing b -> Sing (a :<> b)
sa %:<> sb =
    let a  = fromSing sa
        b  = fromSing sb
        ex = someSymbolVal $ T.unpack $ a <> b
    in case ex of
         SomeSymbol (_ :: Proxy ab) -> unsafeCoerce (SSym :: Sing ab)
infixr 6 %:<>

type (:<>$$$) (x :: Symbol) (y :: Symbol) =
    (:<>) x y
instance SuppressUnusedWarnings (:<>$$) where
  suppressUnusedWarnings = snd ((:<>$$###), ())
data (:<>$$) (x :: Symbol) (y :: TyFun Symbol Symbol)
  = forall arg. KindOf (Apply ((:<>$$) x) arg) ~ KindOf ((:<>$$$) x arg) => (:<>$$###)
type instance Apply ((:<>$$) x) y = (:<>$$$) x y
instance SuppressUnusedWarnings (:<>$) where
  suppressUnusedWarnings = snd ((:<>$###), ())
data (:<>$) (x :: TyFun Symbol (TyFun Symbol Symbol -> Type))
  = forall arg. KindOf (Apply (:<>$) arg) ~ KindOf ((:<>$$) arg) => (:<>$###)
type instance Apply (:<>$) x = (:<>$$) x

-- | The @shows@ functions return a function that prepends the
-- output 'Symbol' to an existing 'Symbol'.  This allows constant-time
-- concatenation of results using function composition.
type SymbolS = Symbol -> Symbol

-- | GHC currently has no notion of type-level 'Char's, so we fake them with
-- single-character 'Symbol's.
type SChar = Symbol

$(singletonsOnly [d|
  class Show a where
    showsPrec :: Nat -> a -> SymbolS
    show_     :: a -> Symbol
    showList  :: [a] -> SymbolS

    showsPrec _ x s = show_ x <> s
    show_ x         = shows x ""
    showList ls   s = showListWith shows ls s

  shows :: Show a => a -> SymbolS
  shows s = showsPrec 0 s

  showListWith :: (a -> SymbolS) -> [a] -> SymbolS
  showListWith _     []     s = "[]" <> s
  showListWith showx (x:xs) s = "["  <> showx x (showl xs)
    where
      showl []     = "]" <> s
      showl (y:ys) = "," <> showx y (showl ys)

  showChar :: SChar -> SymbolS
  showChar = (<>)

  showString :: Symbol -> SymbolS
  showString = (<>)

  showParen :: Bool -> SymbolS -> SymbolS
  showParen b p = if b then showChar "(" . p . showChar ")" else p

  showSpace :: SymbolS
  showSpace = \xs -> " " <> xs

  showCommaSpace :: SymbolS
  showCommaSpace = showString ", "

  appPrec, appPrec1 :: Nat
  appPrec  = 10
  appPrec1 = 11

  instance Show a => Show [a] where
    showsPrec _ = showList

  -- -| This is not an ideal Show instance for Symbol, since the Show instance
  -- for String escapes special characters. Unfortunately, GHC lacks the ability
  -- to case on individual characters in a Symbol (at least, not without GHC
  -- plugins), so this is the best we can do for the time being.
  instance Show Symbol where
    showsPrec _ = showString

  show_tuple :: [SymbolS] -> SymbolS
  show_tuple ss = showChar "("
                . foldr1 (\s r -> s . showChar "," . r) ss
                . showChar ")"

  instance (Show a, Show b) => Show (a,b)  where
    showsPrec _ (a,b) s = show_tuple [shows a, shows b] s

  instance (Show a, Show b, Show c) => Show (a, b, c) where
    showsPrec _ (a,b,c) s = show_tuple [shows a, shows b, shows c] s

  instance (Show a, Show b, Show c, Show d) => Show (a, b, c, d) where
    showsPrec _ (a,b,c,d) s = show_tuple [shows a, shows b, shows c, shows d] s

  instance (Show a, Show b, Show c, Show d, Show e) => Show (a, b, c, d, e) where
    showsPrec _ (a,b,c,d,e) s = show_tuple [shows a, shows b, shows c, shows d, shows e] s

  instance (Show a, Show b, Show c, Show d, Show e, Show f) => Show (a,b,c,d,e,f) where
    showsPrec _ (a,b,c,d,e,f) s = show_tuple [shows a, shows b, shows c, shows d, shows e, shows f] s

  instance (Show a, Show b, Show c, Show d, Show e, Show f, Show g)
          => Show (a,b,c,d,e,f,g) where
    showsPrec _ (a,b,c,d,e,f,g) s
          = show_tuple [shows a, shows b, shows c, shows d, shows e, shows f, shows g] s
  |])

$(promoteOnly [d|
  showsNat :: Nat -> SymbolS
  showsNat 0 = showChar "0"
  showsNat 1 = showChar "1"
  showsNat 2 = showChar "2"
  showsNat 3 = showChar "3"
  showsNat 4 = showChar "4"
  showsNat 5 = showChar "5"
  showsNat 6 = showChar "6"
  showsNat 7 = showChar "7"
  showsNat 8 = showChar "8"
  showsNat 9 = showChar "9"
  showsNat n = showsNat (n `div` 10) . showsNat (n `mod` 10)

  -- https://ghc.haskell.org/trac/ghc/ticket/13652 asks for these in GHC.TypeLits.
  -- That would be nice, since this implementation is horribly slow.
  divmod :: Nat -> Nat -> Nat -> Nat -> (Nat, Nat)
  divmod 0 _ q u = (q, u)
  divmod n y q 0 = divmod (n-1) y (q+1) y
  divmod n y q u = divmod (n-1) y q     (u-1)

  div :: Nat -> Nat -> Nat
  div _ 0 = 0
  div x y = fst (divmod x (y-1) 0 (y-1))

  mod :: Nat -> Nat -> Nat
  mod _ 0 = 0
  mod x y = (y-1) - snd (divmod x (y-1) 0 (y-1))

  |])

-- | Note that this instance is really, really slow, since it uses an inefficient,
-- inductive definition of division behind the hood.
instance PShow Nat where
  type ShowsPrec _ n x = ShowsNat n x

instance SShow Nat where
  sShowsPrec _ sn sx =
    let n = fromSing sn
        x = fromSing sx
        ex = someSymbolVal (P.show n ++ T.unpack x)
    in
    case ex of
      SomeSymbol (_ :: Proxy s) -> unsafeCoerce (SSym :: Sing s)

-- | 'P.show', but with an extra underscore so that its promoted counterpart
-- ('Show_') will not clash with the 'Show' class.
show_ :: P.Show a => a -> String
show_ = P.show

$(singShowInstances [ ''(), ''Maybe, ''Either, ''NonEmpty, ''Bool, ''Ordering ])