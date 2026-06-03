module IbisFS.Verified where

open import IbisFS.Core
open import IbisFS.Basic
open import Janus.Transport using (Transport; idT)
open import Janus.Refine    using (Refine; decodeProof)
open import Data.Product using (Σ; _,_; proj₁; proj₂; ∃-syntax)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Maybe using (Maybe; just; nothing)
open import Relation.Nullary using (¬_; Dec; yes; no)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

-- IbisFS.Verified è il PRIMO modulo del monorepo che dipende da Janus.
-- Realizza il legame *strutturale* fra i due progetti: i path raffinati
-- che IbisFS espone all'utente usano la stessa forma di witness
-- packaging che Janus userà al confine FFI per parlare con Haskell.
-- Stessa firma, stesso `Refine A P (validate : Dec)`, stessa Σ A P al
-- sito di chiamata. Niente di nuovo da inventare al boundary runtime —
-- la prova VIAGGIA invariata da Verified fino a Runtime.POSIX/S3/Azure.
--
-- Pratica: prendi un path "raw", lo passi a `promote`, e ricevi indietro
-- O un `ExistsPath` (carrier di prova di esistenza), O un `FreshPath`
-- (carrier di prova di non-esistenza). Le operazioni raffinate
-- (writeFile-fresh, readFile-existing) ti FORZANO ad avere la prova:
-- non puoi chiamarle con un path non controllato, il typechecker dice no.
module Verified (Path Content : Set) where
  open Lattice Path Content
  open Basic   Path Content

  -- ══════════════════════════════════════════════════════════════════
  -- PREDICATI sull'esistenza
  -- ══════════════════════════════════════════════════════════════════
  -- Exists fs p: "esiste almeno un contenuto al path p in fs".
  -- Multivaluato per costruzione: in un namespace Plan 9-style lo
  -- stesso path può avere più contenuti — qui ne basta UNO per dire
  -- che il path "esiste".
  Exists : FS → Path → Set
  Exists fs p = ∃[ c ] fs (p , c)

  -- NotExists fs p: "p è libero in fs". Negazione costruttiva — è la
  -- prova che NESSUN contenuto vive al path p.
  NotExists : FS → Path → Set
  NotExists fs p = ¬ Exists fs p

  -- ══════════════════════════════════════════════════════════════════
  -- PATH RAFFINATI = Σ Path P con P decidibile
  -- ══════════════════════════════════════════════════════════════════
  -- Sono *tipi dipendenti dal fs*: la stessa Path con prove diverse
  -- vive in tipi diversi. Esattamente quello che Janus.Refine produce
  -- al confine FFI — Σ A P, dove la P è la garanzia portata dentro.
  ExistsPath : FS → Set
  ExistsPath fs = Σ Path (Exists fs)

  FreshPath : FS → Set
  FreshPath fs = Σ Path (NotExists fs)

  -- ══════════════════════════════════════════════════════════════════
  -- IL LEGAME con Janus.Refine
  -- ══════════════════════════════════════════════════════════════════
  -- Esponiamo `Exists fs` come un Refine Path Path:
  --   - transport = idT (siamo in pura Agda, niente Haskell qui)
  --   - P = Exists fs (l'invariante semantico)
  --   - validate = la decidibilità che il consumer fornisce
  --
  -- Quando in futuro `IbisFS.Runtime.POSIX` userà Janus.callChecked
  -- per parlare a System.Directory, riceverà un Path raw da Haskell e
  -- lo decodificherà ATTRAVERSO QUESTO STESSO `existsRefine`. La
  -- prova prodotta sul confine FFI sarà letteralmente la stessa che
  -- Verified produce qui, in pura Agda. Niente di nuovo da inventare
  -- al runtime — solo cambia il `transport` (da idT a un transport
  -- non banale per i tipi del SDK).

  existsRefine : (fs : FS)
               → ((p : Path) → Dec (Exists fs p))
               → Refine Path Path
  existsRefine fs dec = record
    { transport = idT
    ; P         = Exists fs
    ; validate  = dec
    }

  -- decodeProof di existsRefine ci dà gratis: Path → Maybe (ExistsPath fs).
  -- È letteralmente la stessa funzione che Janus.callChecked usa al
  -- confine FFI per decidere "il valore tornato da Haskell rispetta
  -- l'invariante?" — solo che qui H = Path = A.
  tryExists : (fs : FS)
            → ((p : Path) → Dec (Exists fs p))
            → Path → Maybe (ExistsPath fs)
  tryExists fs dec = decodeProof (existsRefine fs dec)

  -- ══════════════════════════════════════════════════════════════════
  -- PROMOTE: classifica un path raw senza perdere informazione
  -- ══════════════════════════════════════════════════════════════════
  -- A differenza di tryExists (yes/no via Maybe), promote restituisce
  -- O ExistsPath O FreshPath: ENTRAMBI rami portano la prova nei tipi.
  -- Nessuna informazione persa al confine — il caller può ragionare
  -- per casi senza dover ri-decidere.
  promote : (fs : FS)
          → ((p : Path) → Dec (Exists fs p))
          → Path → ExistsPath fs ⊎ FreshPath fs
  promote fs dec p with dec p
  ... | yes ex  = inj₁ (p , ex)
  ... | no  ¬ex = inj₂ (p , ¬ex)

  -- ══════════════════════════════════════════════════════════════════
  -- API RAFFINATA
  -- ══════════════════════════════════════════════════════════════════
  -- Queste sono le operazioni che il consumatore RAFFINATO chiama. Non
  -- accettano un Path raw — accettano un *path con prova*. Il
  -- typechecker rende impossibile chiamarle senza aver fatto promote
  -- (o senza aver costruito la prova in altro modo). Niente più
  -- "ho dimenticato di controllare se il file esisteva".

  -- writeFile-fresh: scrivi a un path GIÀ DIMOSTRATO libero.
  writeFile-fresh : (fs : FS) → FreshPath fs → Content → FS
  writeFile-fresh fs (p , _) c = writeFile p c fs

  -- readFile-existing: leggi a un path GIÀ DIMOSTRATO esistente.
  -- Restituisce IL contenuto testimone (estratto dalla prova) E la
  -- prova che è davvero in fs. Niente Maybe — è totale.
  readFile-existing : (fs : FS) (ep : ExistsPath fs)
                    → Σ Content (λ c → fs (proj₁ ep , c))
  readFile-existing fs (p , c , prf) = c , prf

  -- ══════════════════════════════════════════════════════════════════
  -- TEOREMI: i tipi raffinati propagano le invarianti
  -- ══════════════════════════════════════════════════════════════════

  -- ── writeFile crea esistenza ─────────────────────────────────────
  -- Per OGNI fs e qualunque (p,c), dopo writeFile il path è Exists.
  -- È il pagamento dei tipi raffinati: l'invariante "il path esiste"
  -- nasce per costruzione dall'operazione di scrittura. La prova:
  -- inj₂ (refl, refl), cioè "la nuova entry È esattamente (p,c)".
  writeFile-creates : ∀ fs p c → Exists (writeFile p c fs) p
  writeFile-creates fs p c = c , inj₂ (refl , refl)

  -- ── fresh → exists: la promozione attraverso la scrittura ────────
  -- Corollario diretto: scrivendo a un FreshPath, otteniamo un
  -- ExistsPath del filesystem risultante. È la PROVA che le
  -- operazioni di mutazione propagano correttamente le invarianti
  -- raffinate — il caller può ENCATENARE writeFile-fresh seguiti da
  -- readFile-existing senza ri-decidere nulla.
  fresh→exists : ∀ fs (fp : FreshPath fs) c
               → ExistsPath (writeFile-fresh fs fp c)
  fresh→exists fs (p , _) c = p , writeFile-creates fs p c

  -- ── overwriteFile crea esistenza (anche da fs non vuoto) ────────
  -- L'analogo per overwriteFile. La prova è identica: l'unione
  -- aggiunge il singoletto al di là di qualunque eliminazione.
  overwriteFile-creates : ∀ fs p c → Exists (overwriteFile p c fs) p
  overwriteFile-creates fs p c = c , inj₂ (refl , refl)
