module IbisFS.Laws where

open import IbisFS.Core
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Product using (_×_; _,_; proj₁)
open import Data.Empty using (⊥)

-- Le tre leggi del reticolo per `_∪_`, dimostrate per ogni scelta di
-- Path e Content: la rappresentazione (2) le rende corollari di
-- isomorfismi banali sui tipi somma.
module Laws (Path Content : Set) where
  open Lattice Path Content

  -- ══════════════════════════════════════════════════════════════════
  -- LEGGE 1 — COMMUTATIVITÀ:    a ∪ b  ≈  b ∪ a
  -- ══════════════════════════════════════════════════════════════════
  -- Se la prova viene da a (inj₁) la metti in inj₂ di b∪a, e viceversa.
  -- È l'isomorfismo X ⊎ Y ≃ Y ⊎ X.
  ∪-comm : ∀ a b → (a ∪ b) ≈ (b ∪ a)
  ∪-comm a b = record { to = swap ; from = swap }
    where
      swap : ∀ {X Y : Set} → X ⊎ Y → Y ⊎ X
      swap (inj₁ x) = inj₂ x
      swap (inj₂ y) = inj₁ y

  -- ══════════════════════════════════════════════════════════════════
  -- LEGGE 2 — ASSOCIATIVITÀ:   (a ∪ b) ∪ c  ≈  a ∪ (b ∪ c)
  -- ══════════════════════════════════════════════════════════════════
  -- L'isomorfismo (X⊎Y)⊎Z ≃ X⊎(Y⊎Z). Quattro casi per ogni direzione.
  ∪-assoc : ∀ a b c → ((a ∪ b) ∪ c) ≈ (a ∪ (b ∪ c))
  ∪-assoc a b c = record { to = fwd ; from = bwd }
    where
      fwd : ∀ {e} → ((a ∪ b) ∪ c) e → (a ∪ (b ∪ c)) e
      fwd (inj₁ (inj₁ x)) = inj₁ x
      fwd (inj₁ (inj₂ y)) = inj₂ (inj₁ y)
      fwd (inj₂ z)        = inj₂ (inj₂ z)

      bwd : ∀ {e} → (a ∪ (b ∪ c)) e → ((a ∪ b) ∪ c) e
      bwd (inj₁ x)        = inj₁ (inj₁ x)
      bwd (inj₂ (inj₁ y)) = inj₁ (inj₂ y)
      bwd (inj₂ (inj₂ z)) = inj₂ z

  -- ══════════════════════════════════════════════════════════════════
  -- LEGGE 3 — IDEMPOTENZA:     a ∪ a  ≈  a
  -- ══════════════════════════════════════════════════════════════════
  -- L'andata "schiaccia" le due copie di a in una; il ritorno usa
  -- arbitrariamente inj₁ (anche inj₂ andrebbe). NB: l'idempotenza
  -- *fino a ≈* è onesta — non c'è informazione persa a livello di
  -- entries, anche se la "provenienza" inj₁/inj₂ si perde.
  ∪-idem : ∀ a → (a ∪ a) ≈ a
  ∪-idem a = record { to = squash ; from = inj₁ }
    where
      squash : ∀ {e} → (a ∪ a) e → a e
      squash (inj₁ x) = x
      squash (inj₂ x) = x

  -- ══════════════════════════════════════════════════════════════════
  -- LEGGE 4 — COMMUTATIVITÀ di ∩:    a ∩ b  ≈  b ∩ a
  -- ══════════════════════════════════════════════════════════════════
  -- Duale di ∪-comm: l'isomorfismo X × Y ≃ Y × X. swap di coppie.
  ∩-comm : ∀ a b → (a ∩ b) ≈ (b ∩ a)
  ∩-comm a b = record { to = swap ; from = swap }
    where
      swap : ∀ {X Y : Set} → X × Y → Y × X
      swap (x , y) = y , x

  -- ══════════════════════════════════════════════════════════════════
  -- LEGGE 5 — ASSOCIATIVITÀ di ∩:   (a ∩ b) ∩ c  ≈  a ∩ (b ∩ c)
  -- ══════════════════════════════════════════════════════════════════
  -- Riassociazione delle coppie annidate: (X×Y)×Z ≃ X×(Y×Z).
  ∩-assoc : ∀ a b c → ((a ∩ b) ∩ c) ≈ (a ∩ (b ∩ c))
  ∩-assoc a b c = record { to = fwd ; from = bwd }
    where
      fwd : ∀ {e} → ((a ∩ b) ∩ c) e → (a ∩ (b ∩ c)) e
      fwd ((x , y) , z) = x , (y , z)
      bwd : ∀ {e} → (a ∩ (b ∩ c)) e → ((a ∩ b) ∩ c) e
      bwd (x , (y , z)) = (x , y) , z

  -- ══════════════════════════════════════════════════════════════════
  -- LEGGE 6 — IDEMPOTENZA di ∩:     a ∩ a  ≈  a
  -- ══════════════════════════════════════════════════════════════════
  -- to: butta via la seconda copia della prova. from: la duplica.
  ∩-idem : ∀ a → (a ∩ a) ≈ a
  ∩-idem a = record { to = proj₁ ; from = λ x → x , x }

  -- ══════════════════════════════════════════════════════════════════
  -- LEGGE 7 — DISTRIBUTIVITÀ ∩ su ∪:
  --   a ∩ (b ∪ c)  ≈  (a ∩ b) ∪ (a ∩ c)
  -- ══════════════════════════════════════════════════════════════════
  -- Operativamente: "leggere da (b unito c) intersecando con a" è uguale
  -- a "leggere separatamente da (a∩b) e da (a∩c) e unire". È ciò che
  -- giustifica `readFile p (merge fs₁ fs₂) ≡ readFile p fs₁ ∪ readFile p fs₂`.
  ∩-∪-distrib : ∀ a b c → (a ∩ (b ∪ c)) ≈ ((a ∩ b) ∪ (a ∩ c))
  ∩-∪-distrib a b c = record { to = fwd ; from = bwd }
    where
      fwd : ∀ {e} → (a ∩ (b ∪ c)) e → ((a ∩ b) ∪ (a ∩ c)) e
      fwd (x , inj₁ y) = inj₁ (x , y)
      fwd (x , inj₂ z) = inj₂ (x , z)
      bwd : ∀ {e} → ((a ∩ b) ∪ (a ∩ c)) e → (a ∩ (b ∪ c)) e
      bwd (inj₁ (x , y)) = x , inj₁ y
      bwd (inj₂ (x , z)) = x , inj₂ z

  -- ══════════════════════════════════════════════════════════════════
  -- LEGGE 8 — DISTRIBUTIVITÀ ∪ su ∩:
  --   a ∪ (b ∩ c)  ≈  (a ∪ b) ∩ (a ∪ c)
  -- ══════════════════════════════════════════════════════════════════
  -- L'altra metà: insieme con la legge 7 chiude IbisFS.Core come
  -- *reticolo distributivo* (non solo semigruppo con qualche legge).
  -- bwd: se uno dei due lati della coppia è inj₁ x, possiamo restituire
  -- inj₁ x; solo se entrambi sono inj₂ otteniamo la coppia destra.
  ∪-∩-distrib : ∀ a b c → (a ∪ (b ∩ c)) ≈ ((a ∪ b) ∩ (a ∪ c))
  ∪-∩-distrib a b c = record { to = fwd ; from = bwd }
    where
      fwd : ∀ {e} → (a ∪ (b ∩ c)) e → ((a ∪ b) ∩ (a ∪ c)) e
      fwd (inj₁ x)       = inj₁ x , inj₁ x
      fwd (inj₂ (y , z)) = inj₂ y , inj₂ z
      bwd : ∀ {e} → ((a ∪ b) ∩ (a ∪ c)) e → (a ∪ (b ∩ c)) e
      bwd (inj₁ x , _)       = inj₁ x
      bwd (inj₂ _ , inj₁ x)  = inj₁ x
      bwd (inj₂ y , inj₂ z)  = inj₂ (y , z)

  -- ══════════════════════════════════════════════════════════════════
  -- LEGGI 9-10 — IDENTITÀ:  ∅ è zero di ∪
  --   a ∪ ∅  ≈  a        ∅ ∪ a  ≈  a
  -- ══════════════════════════════════════════════════════════════════
  -- Sblocca `IbisFS.Basic`: writeFile può partire dal filesystem vuoto e
  -- aggiungere singoletti via ∪ senza tassa algebrica. Il caso inj₂ è
  -- vacuo (pattern absurd) perché ⊥ è inabitato — è il typechecker che
  -- *esegue* la prova per noi.
  ∪-identityʳ : ∀ a → (a ∪ ∅) ≈ a
  ∪-identityʳ a = record { to = drop ; from = inj₁ }
    where
      drop : ∀ {e} → (a ∪ ∅) e → a e
      drop (inj₁ x) = x
      drop (inj₂ ())

  ∪-identityˡ : ∀ a → (∅ ∪ a) ≈ a
  ∪-identityˡ a = record { to = drop ; from = inj₂ }
    where
      drop : ∀ {e} → (∅ ∪ a) e → a e
      drop (inj₁ ())
      drop (inj₂ x) = x

  -- ══════════════════════════════════════════════════════════════════
  -- LEGGI 11-12 — CONGRUENZA di ∪ e ∩ per ≈
  --   a ≈ a'  →  b ≈ b'  →  a ∪ b  ≈  a' ∪ b'
  -- ══════════════════════════════════════════════════════════════════
  -- Senza queste due, riscrivere "dentro" un ∪/∩ richiederebbe ricostruire
  -- la prova a mano ogni volta. Con queste, ≈ è una congruenza per
  -- l'algebra del reticolo: si compone come ≡, mantenendo la costruttività.
  ∪-cong : ∀ {a a' b b'} → a ≈ a' → b ≈ b' → (a ∪ b) ≈ (a' ∪ b')
  ∪-cong a≈a' b≈b' = record
    { to   = λ { (inj₁ x) → inj₁ (to   a≈a' x)
               ; (inj₂ y) → inj₂ (to   b≈b' y) }
    ; from = λ { (inj₁ x) → inj₁ (from a≈a' x)
               ; (inj₂ y) → inj₂ (from b≈b' y) }
    }

  ∩-cong : ∀ {a a' b b'} → a ≈ a' → b ≈ b' → (a ∩ b) ≈ (a' ∩ b')
  ∩-cong a≈a' b≈b' = record
    { to   = λ { (x , y) → to   a≈a' x , to   b≈b' y }
    ; from = λ { (x , y) → from a≈a' x , from b≈b' y }
    }

  -- ══════════════════════════════════════════════════════════════════
  -- LEGGI 13-14 — ASSORBIMENTO:
  --   a ∪ (a ∩ b)  ≈  a      a ∩ (a ∪ b)  ≈  a
  -- ══════════════════════════════════════════════════════════════════
  -- Insieme con commutatività/associatività/idempotenza, l'assorbimento
  -- certifica che (FS, ∪, ∩) è un *reticolo* nel senso classico — non
  -- "due semigruppi che si parlano". Operativamente: aggiungere a un fs
  -- una sua sottoparte non lo cambia (1); restringere un fs alla sua
  -- estensione non lo cambia (2).
  ∪-absorbs-∩ : ∀ a b → (a ∪ (a ∩ b)) ≈ a
  ∪-absorbs-∩ a b = record { to = squash ; from = inj₁ }
    where
      squash : ∀ {e} → (a ∪ (a ∩ b)) e → a e
      squash (inj₁ x)       = x
      squash (inj₂ (x , _)) = x

  ∩-absorbs-∪ : ∀ a b → (a ∩ (a ∪ b)) ≈ a
  ∩-absorbs-∪ a b = record
    { to   = proj₁
    ; from = λ x → x , inj₁ x
    }
