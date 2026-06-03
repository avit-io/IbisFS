module Examples.S3 where

-- Lifecycle demo per IbisFS.Runtime.S3 (backend in-memory simulator).
-- Mostra il flow completo: chiave libera → put → chiave esiste → get
-- → delete → chiave libera di nuovo. Lo stato attraversa il confine
-- FFI sei volte, conservato in un IORef Map T.Text T.Text.
--
-- Compilazione + esecuzione:
--   nix develop
--   agda --library-file=$AGDA_DIR/libraries --compile --compile-dir=Examples Examples/S3.agda
--   ./Examples/S3

open import IbisFS.Runtime.S3
open import Janus.FFI using (_>>=_; return)
open import Agda.Builtin.IO using (IO)
open import Agda.Builtin.Unit using (⊤)
open import Agda.Builtin.String using (String)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.String using (_++_)

postulate putStrLn : String → IO ⊤
{-# FOREIGN GHC import qualified Data.Text.IO as TIO #-}
{-# COMPILE GHC putStrLn = TIO.putStrLn #-}

-- ── prettyprint ────────────────────────────────────────────────────
describe : ExistsPath s3FS ⊎ FreshPath s3FS → String
describe (inj₁ _) = "esiste"
describe (inj₂ _) = "libero"

describeErr : S3Error → String
describeErr noSuchKey       = "NoSuchKey"
describeErr accessDenied    = "AccessDenied"
describeErr (serviceError s) = "ServiceError: " ++ s
describeErr (otherS3Error s) = "Other: " ++ s

showR : Result S3Error Content → String
showR (ok c)  = "OK | content = \"" ++ c ++ "\""
showR (err e) = "ERR | " ++ describeErr e

showU : Result S3Error ⊤ → String
showU (ok _)  = "OK"
showU (err e) = "ERR | " ++ describeErr e

-- ── azioni condizionate sulla classificazione ─────────────────────
doWrite : Content → ExistsPath s3FS ⊎ FreshPath s3FS → IO ⊤
doWrite _  (inj₁ _)  = putStrLn "  ↳ skip (già esiste)"
doWrite c  (inj₂ fp) = putObject-fresh-IO fp c >>= λ r → putStrLn ("  ↳ put " ++ showU r)

doRead : ExistsPath s3FS ⊎ FreshPath s3FS → IO ⊤
doRead (inj₁ ep) = getObject-IO ep >>= λ r → putStrLn ("  ↳ get " ++ showR r)
doRead (inj₂ _)  = putStrLn "  ↳ skip (non esiste)"

doDelete : ExistsPath s3FS ⊎ FreshPath s3FS → IO ⊤
doDelete (inj₁ ep) = deleteObject-IO ep >>= λ r → putStrLn ("  ↳ delete " ++ showU r)
doDelete (inj₂ _)  = putStrLn "  ↳ skip (non esiste)"

-- ── lifecycle ──────────────────────────────────────────────────────
key : String
key = "config/answer.json"

payload : Content
payload = "{\"answer\":42}"

step1 step2 step3 step4 step5 step6 : IO ⊤
step1 = putStrLn "[1] promote (atteso libero):"          >>= λ _ → promote-IO key >>= λ c → putStrLn ("  ↳ " ++ describe c)
step2 = putStrLn "[2] put (se libero):"                  >>= λ _ → promote-IO key >>= λ c → doWrite payload c
step3 = putStrLn "[3] promote dopo put (atteso esiste):" >>= λ _ → promote-IO key >>= λ c → putStrLn ("  ↳ " ++ describe c)
step4 = putStrLn "[4] get (se esiste):"                  >>= λ _ → promote-IO key >>= λ c → doRead c
step5 = putStrLn "[5] delete (se esiste):"               >>= λ _ → promote-IO key >>= λ c → doDelete c
step6 = putStrLn "[6] promote dopo delete (atteso libero):" >>= λ _ → promote-IO key >>= λ c → putStrLn ("  ↳ " ++ describe c)

main : IO ⊤
main =
  putStrLn "IbisFS.Runtime.S3 demo — lifecycle su bucket in-memory" >>= λ _ →
  putStrLn "" >>= λ _ →
  step1 >>= λ _ → step2 >>= λ _ → step3 >>= λ _ →
  step4 >>= λ _ → step5 >>= λ _ → step6 >>= λ _ →
  putStrLn "fine"
