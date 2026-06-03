module Main where

open import IbisFS.Runtime.POSIX
open import Janus.FFI using (_>>=_; return)
open import Agda.Builtin.IO using (IO)
open import Agda.Builtin.Unit using (⊤)
open import Agda.Builtin.String using (String)
open import Data.Sum using (_⊎_; inj₁; inj₂)

postulate putStrLn : String → IO ⊤
{-# FOREIGN GHC import qualified Data.Text.IO as TIO #-}
{-# COMPILE GHC putStrLn = TIO.putStrLn #-}

-- ── il demo del bridge: refined paths dal mondo reale ──────────────
-- promote-IO decide via System.Directory; il tipo del risultato è
-- ExistsPath ⊎ FreshPath. Niente più Bool nudi che girano nel codice.
check : String → IO ⊤
check p =
  promote-IO p >>= λ classification →
  putStrLn (report classification)
  where
    report : ExistsPath posixFS ⊎ FreshPath posixFS → String
    report (inj₁ _) = "  ↳ esiste (ExistsPath posixFS in mano)"
    report (inj₂ _) = "  ↳ libero (FreshPath posixFS in mano)"

-- ── il demo del Result: errori tipati al confine ──────────────────
-- readFile-IO consuma un ExistsPath e ritorna Result FSError Content.
-- Il caller DEVE pattern-matchare entrambi i casi — il typechecker
-- non gli permette di ignorare il fallimento.
readDemo : String → IO ⊤
readDemo p =
  promote-IO p >>= λ classification →
  consume classification
  where
    describeErr : FSError → String
    describeErr doesNotExist     = "ENOENT (TOCTOU? cancellato fra promote e read)"
    describeErr permissionDenied = "EACCES (permessi insufficienti)"
    describeErr (otherFSError s) = s

    showResult : Result FSError Content → String
    showResult (ok _)    = "  ↳ letto"
    showResult (err e)   = "  ↳ errore: " ++ describeErr e
      where open import Data.String using (_++_)

    consume : ExistsPath posixFS ⊎ FreshPath posixFS → IO ⊤
    consume (inj₁ ep)    = readFile-IO ep >>= λ r → putStrLn (showResult r)
    consume (inj₂ _)     = putStrLn "  ↳ libero, niente da leggere"

main : IO ⊤
main =
  putStrLn "IbisFS.Runtime.POSIX demo — refined paths + Result al confine" >>= λ _ →
  putStrLn "" >>= λ _ →
  putStrLn "PROMOTE /etc/hostname:"     >>= λ _ →  check "/etc/hostname"   >>= λ _ →
  putStrLn "PROMOTE /no/such/path:"     >>= λ _ →  check "/no/such/path"   >>= λ _ →
  putStrLn "" >>= λ _ →
  putStrLn "READ /etc/hostname:"        >>= λ _ →  readDemo "/etc/hostname" >>= λ _ →
  putStrLn "READ /etc/shadow:"          >>= λ _ →  readDemo "/etc/shadow"   >>= λ _ →
  putStrLn "READ /no/such/path:"        >>= λ _ →  readDemo "/no/such/path" >>= λ _ →
  putStrLn "fine"
