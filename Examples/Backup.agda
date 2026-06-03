module Examples.Backup where

-- ┌──────────────────────────────────────────────────────────────────┐
-- │  Use case: backup POSIX → S3                                      │
-- │                                                                   │
-- │  Legge un file locale, lo carica come oggetto S3 con chiave       │
-- │  derivata. La pipeline ha quattro possibili modi di fallimento,  │
-- │  TUTTI tipizzati e tutti FORZATI dal compilatore:                 │
-- │                                                                   │
-- │    POSIX classified inj₂ → SOURCE_MISSING                        │
-- │    POSIX read err       → SOURCE_READ_FAILED  (EACCES, ENOENT…)  │
-- │    S3 classified inj₁   → TARGET_EXISTS  (no overwrite!)         │
-- │    S3 put err           → TARGET_UPLOAD_FAILED                    │
-- │                                                                   │
-- │  Quello che mostra l'esempio:                                     │
-- │   * lo stesso `ExistsPath`/`FreshPath` di Verified attraversa     │
-- │     DUE runtime diversi (POSIX e S3) senza adattatori             │
-- │   * la pipeline è una serie di pattern match esaustivi: niente   │
-- │     fallback nascosto, niente eccezione che sfugge                │
-- │   * il caller di `backup` riceve uno String di esito CHE NON      │
-- │     PUÒ MAI ESSERE "ho dimenticato di gestire il caso X"         │
-- └──────────────────────────────────────────────────────────────────┘
--
-- Esecuzione:
--   agda --library-file=$AGDA_DIR/libraries --compile --compile-dir=Examples \
--        Examples/Backup.agda
--   ./Examples/Backup

import IbisFS.Runtime.POSIX as P
import IbisFS.Runtime.S3    as S
open import IbisFS.Runtime.Result using (Result; err; ok)
open import Janus.FFI using (_>>=_; return)
open import Agda.Builtin.IO using (IO)
open import Agda.Builtin.Unit using (⊤)
open import Agda.Builtin.String using (String)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.String using (_++_)

postulate putStrLn : String → IO ⊤
{-# FOREIGN GHC import qualified Data.Text.IO as TIO #-}
{-# COMPILE GHC putStrLn = TIO.putStrLn #-}

-- ── error formatters ──────────────────────────────────────────────
describeP : P.FSError → String
describeP P.doesNotExist     = "ENOENT"
describeP P.permissionDenied = "EACCES"
describeP (P.otherFSError s) = s

describeS : S.S3Error → String
describeS S.noSuchKey        = "NoSuchKey"
describeS S.accessDenied     = "AccessDenied"
describeS (S.serviceError s) = "ServiceError: " ++ s
describeS (S.otherS3Error s) = s

-- ── la pipeline ───────────────────────────────────────────────────
-- Quattro step espliciti, ognuno con la sua direzione d'errore.
-- Notiamo che `body : P.Content = String = S.Content`: la stringa
-- letta da POSIX scivola senza adattatori nel put di S3.
-- NB: Agda 2.8 nei `where` non ammette forward references senza
-- `mutual`. Definiamo gli step in ordine INVERSO (step4 prima, step1
-- ultimo): la lettura algoritmica è dal basso verso l'alto.
backup : String → String → IO String
backup posixSrc s3Dst =
  P.promote-IO posixSrc >>= step1
  where
    step4 : Result S.S3Error ⊤ → IO String
    step4 (ok _)  = return ("OK:                    " ++ posixSrc ++ " → s3://" ++ s3Dst)
    step4 (err e) = return ("TARGET_UPLOAD_FAILED:  " ++ describeS e)

    step3 : S.Content → S.ExistsPath S.s3FS ⊎ S.FreshPath S.s3FS → IO String
    step3 _    (inj₁ _)        = return ("TARGET_EXISTS:         " ++ s3Dst)
    step3 body (inj₂ dstFresh) = S.putObject-fresh-IO dstFresh body >>= step4

    step2 : Result P.FSError P.Content → IO String
    step2 (err e)   = return ("SOURCE_READ_FAILED:    " ++ describeP e)
    step2 (ok body) = S.promote-IO s3Dst >>= step3 body

    step1 : P.ExistsPath P.posixFS ⊎ P.FreshPath P.posixFS → IO String
    step1 (inj₂ _)         = return ("SOURCE_MISSING:        " ++ posixSrc)
    step1 (inj₁ srcExists) = P.readFile-IO srcExists >>= step2

-- ── il demo: tutti e quattro i possibili esiti ────────────────────
main : IO ⊤
main =
  putStrLn "Esempio: Backup — POSIX → S3 cross-runtime" >>= λ _ →
  putStrLn "──────────────────────────────────────────" >>= λ _ →
  putStrLn "" >>= λ _ →
  putStrLn "[1] caso felice (source esiste, target libero)" >>= λ _ →
  backup "/etc/hostname" "backups/hostname-2026-06-03" >>= λ r1 →
  putStrLn ("    " ++ r1) >>= λ _ →
  putStrLn "" >>= λ _ →
  putStrLn "[2] source missing (file non esistente)" >>= λ _ →
  backup "/no/such/file" "backups/whatever" >>= λ r2 →
  putStrLn ("    " ++ r2) >>= λ _ →
  putStrLn "" >>= λ _ →
  putStrLn "[3] target esiste (re-backup della stessa chiave)" >>= λ _ →
  backup "/etc/hostname" "backups/hostname-2026-06-03" >>= λ r3 →
  putStrLn ("    " ++ r3) >>= λ _ →
  putStrLn "" >>= λ _ →
  putStrLn "[4] source no read (permessi insufficienti)" >>= λ _ →
  backup "/etc/shadow" "backups/shadow-2026-06-03" >>= λ r4 →
  putStrLn ("    " ++ r4) >>= λ _ →
  putStrLn "fine"
