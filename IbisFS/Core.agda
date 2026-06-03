module IbisFS.Core where

open import Data.Product using (_×_; _,_)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Empty using (⊥)
open import Relation.Nullary using (¬_)

-- L'algebra non conosce la struttura interna di Path o Content: è
-- parametrizzata su entrambi. Le raffinature concrete (path normalizzati,
-- contenuto = bytes, equality decidibile) vivono in moduli separati e
-- istanziano questo `Lattice` quando serve.
module Lattice (Path Content : Set) where

  Entry : Set
  Entry = Path × Content

  -- ── RAPPRESENTAZIONE (2) ────────────────────────────────────────────
  -- Un filesystem È un predicato su Entry: per ogni (p,c), un *tipo*
  -- "prova che l'entry sta nel filesystem". Multivaluato per costruzione:
  -- lo stesso Path può avere prove per più Content distinti — ed è ciò
  -- che fa di IbisFS un reticolo onesto (Plan 9 union-directory style)
  -- invece di una mappa parziale con conflitti da risolvere a mano.
  FS : Set₁
  FS = Entry → Set

  -- ── OPERAZIONI DEL RETICOLO ────────────────────────────────────────

  -- Il filesystem vuoto: nessuna entry ha prova di stare dentro.
  ∅ : FS
  ∅ _ = ⊥

  -- Unione: a ∪ b contiene un'entry se la contiene a OPPURE b.
  -- inj₁ / inj₂ identificano la "provenienza" della prova — utile dopo
  -- per `merge` con tracciamento.
  _∪_ : FS → FS → FS
  (a ∪ b) e = a e ⊎ b e

  -- Intersezione: a ∩ b contiene un'entry se la contengono entrambi.
  -- La prova è la coppia delle due testimonianze.
  _∩_ : FS → FS → FS
  (a ∩ b) e = a e × b e

  -- Complemento relativo (set difference): a \ b contiene un'entry di
  -- a per cui NON c'è prova in b. È il complemento che ti serve davvero
  -- per `deleteFile`: deleteFile p fs = fs \ {entries-at p}. Non
  -- richiede un "universo" di tutti i path possibili.
  _\\_ : FS → FS → FS
  (a \\ b) e = a e × ¬ (b e)

  infixl 6 _∪_
  infixl 7 _∩_
  infixl 6 _\\_

  -- ── UGUAGLIANZA ESTENSIONALE ────────────────────────────────────────
  -- Due filesystem sono uguali se hanno le stesse entries. NON usiamo
  -- _≡_ su funzioni: ciò chiederebbe extensionality come postulato e
  -- inquinerebbe le prove. Bastano andata e ritorno per ogni entry.
  --
  -- ≈ è una congruenza setoide: rifl., simm., trans. (sotto).
  record _≈_ (a b : FS) : Set where
    field
      to   : ∀ {e} → a e → b e
      from : ∀ {e} → b e → a e
  open _≈_ public

  infix 4 _≈_

  -- ── leggi del setoide ──────────────────────────────────────────────
  ≈-refl : ∀ {a} → a ≈ a
  ≈-refl = record { to = λ x → x ; from = λ x → x }

  ≈-sym : ∀ {a b} → a ≈ b → b ≈ a
  ≈-sym a≈b = record { to = from a≈b ; from = to a≈b }

  ≈-trans : ∀ {a b c} → a ≈ b → b ≈ c → a ≈ c
  ≈-trans a≈b b≈c = record
    { to   = λ x → to   b≈c (to   a≈b x)
    ; from = λ x → from a≈b (from b≈c x)
    }
