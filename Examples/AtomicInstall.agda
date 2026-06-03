module Examples.AtomicInstall where

-- ┌──────────────────────────────────────────────────────────────────┐
-- │  Use case: install-once                                           │
-- │                                                                   │
-- │  Un installer scrive un file di configurazione in /tmp (o /etc). │
-- │  REGOLA: deve CREARE il file se libero, RIFIUTARSI di sovrascrivere
-- │  se esiste già. In codice non-tipato il pattern è:                │
-- │                                                                   │
-- │    if exists(p): refuse()                                         │
-- │    else: write(p, c)                                              │
-- │                                                                   │
-- │  ...e il typechecker non protegge da chi dimentica il check.     │
-- │                                                                   │
-- │  In IbisFS, `writeFile-fresh-IO` ACCETTA SOLO `FreshPath posixFS`.│
-- │  È STRUTTURALMENTE IMPOSSIBILE sovrascrivere — il typechecker      │
-- │  non sa neanche cosa significherebbe `writeFile-fresh-IO` su      │
-- │  un `ExistsPath`. Il check è impossibile da dimenticare perché    │
-- │  `promote-IO` lo restituisce nei tipi.                            │
-- └──────────────────────────────────────────────────────────────────┘
--
-- Esecuzione:
--   agda --library-file=$AGDA_DIR/libraries --compile --compile-dir=Examples \
--        Examples/AtomicInstall.agda
--   ./Examples/AtomicInstall

open import IbisFS.Runtime.POSIX
open import Janus.FFI using (_>>=_; return)
open import Agda.Builtin.IO using (IO)
open import Agda.Builtin.Unit using (⊤; tt)
open import Agda.Builtin.String using (String)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.String using (_++_)

postulate putStrLn : String → IO ⊤
{-# FOREIGN GHC import qualified Data.Text.IO as TIO #-}
{-# COMPILE GHC putStrLn = TIO.putStrLn #-}

describeError : FSError → String
describeError doesNotExist     = "ENOENT"
describeError permissionDenied = "EACCES"
describeError (otherFSError s) = s

-- ── il pattern ────────────────────────────────────────────────────
-- `install` ritorna una stringa di esito. Le due strade dopo promote-IO
-- sono FORZATE dal tipo somma:
--   inj₁ ExistsPath → REFUSED (writeFile-fresh-IO non typecheckerebbe)
--   inj₂ FreshPath  → WRITE (la chiamata vive SOLO qui)
install : String → Content → IO String
install path body =
  promote-IO path >>= λ classification → go classification
  where
    putOnFresh : FreshPath posixFS → IO String
    putOnFresh fresh =
      writeFile-fresh-IO fresh body >>= λ result → return (format result)
      where
        format : Result FSError ⊤ → String
        format (ok _)  = "INSTALLED:        " ++ path
        format (err e) = "WRITE_FAILED:     " ++ describeError e

    go : ExistsPath posixFS ⊎ FreshPath posixFS → IO String
    go (inj₁ _)     = return ("REFUSED (esiste): " ++ path)
    go (inj₂ fresh) = putOnFresh fresh

-- ── helper: cleanup ───────────────────────────────────────────────
cleanup : String → IO ⊤
cleanup path =
  promote-IO path >>= λ classification → go classification
  where
    go : ExistsPath posixFS ⊎ FreshPath posixFS → IO ⊤
    go (inj₁ ep) = removeFile-IO ep >>= λ _ → return tt
    go (inj₂ _)  = return tt

-- ── helper: readback per verificare quale body è sul disco ────────
readback : String → IO ⊤
readback path =
  promote-IO path >>= λ classification → go classification
  where
    showR : Result FSError Content → String
    showR (ok body) = "  on disk:        \"" ++ body ++ "\""
    showR (err e)   = "  read failed:    " ++ describeError e

    go : ExistsPath posixFS ⊎ FreshPath posixFS → IO ⊤
    go (inj₁ ep) = readFile-IO ep >>= λ r → putStrLn (showR r)
    go (inj₂ _)  = putStrLn "  (file missing)"

-- ── il demo ───────────────────────────────────────────────────────
configPath : String
configPath = "/tmp/ibisfs-demo-config.cfg"

initialBody : Content
initialBody = "log_level=info; timeout=30"

attackerBody : Content
attackerBody = "log_level=OFF; user=attacker"

main : IO ⊤
main =
  putStrLn "Esempio: AtomicInstall — install-once via refined types" >>= λ _ →
  putStrLn "────────────────────────────────────────────────────────" >>= λ _ →
  putStrLn ("target:  " ++ configPath) >>= λ _ →
  putStrLn "" >>= λ _ →
  cleanup configPath >>= λ _ →
  putStrLn "[1] prima install (atteso INSTALLED)" >>= λ _ →
  install configPath initialBody >>= λ r1 →
  putStrLn ("    " ++ r1) >>= λ _ →
  putStrLn "" >>= λ _ →
  putStrLn "[2] secondo install con body diverso (atteso REFUSED)" >>= λ _ →
  install configPath attackerBody >>= λ r2 →
  putStrLn ("    " ++ r2) >>= λ _ →
  putStrLn "" >>= λ _ →
  putStrLn "[3] readback: il body iniziale è preservato" >>= λ _ →
  readback configPath >>= λ _ →
  putStrLn "" >>= λ _ →
  cleanup configPath >>= λ _ →
  putStrLn "(cleanup eseguito)"
