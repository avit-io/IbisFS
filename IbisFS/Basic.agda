module IbisFS.Basic where

open import IbisFS.Core
open import IbisFS.Laws
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Empty using (⊥-elim)
open import Relation.Binary.PropositionalEquality using (_≡_; _≢_; refl; sym; trans)

-- IbisFS.Basic è la *façade* CRUD: l'API che il programmatore medio si
-- aspetta da un filesystem (writeFile, readFile, deleteFile) costruita
-- come *combinazioni* delle operazioni del reticolo. Niente di nuovo
-- sotto: i teoremi caratterizzanti dei CRUD sono corollari delle 14
-- leggi di Core.
--
-- Path e Content restano parametri astratti: per la sola algebra basta
-- l'uguaglianza proposizionale _≡_, non serve decidibilità. La
-- decidibilità arriverà in `Plan9` / `Verified` / `Runtime.*`.
module Basic (Path Content : Set) where
  open Lattice Path Content
  open Laws    Path Content

  -- ── SINGOLETTI DEL RETICOLO ──────────────────────────────────────

  -- ⌊ e ⌋: il filesystem che contiene esattamente l'entry e.
  -- Membership: "(p', c') sta in ⌊(p,c)⌋" ≡ "p ≡ p' E c ≡ c'".
  ⌊_⌋ : Entry → FS
  ⌊ (p , c) ⌋ (p' , c') = (p ≡ p') × (c ≡ c')

  -- pathSlice p: tutte le entries con path = p, qualunque contenuto.
  -- È la "vista del filesystem filtrata per path" — l'oggetto naturale
  -- con cui intersecare per fare `readFile` e `deleteFile`.
  pathSlice : Path → FS
  pathSlice p (p' , _) = p ≡ p'

  -- ── API DERIVATA ─────────────────────────────────────────────────
  -- writeFile, readFile, deleteFile NON sono primitive: sono identità
  -- algebriche sopra ∪, ∩, \\. Ogni proprietà che vorrai dimostrare
  -- su di essi scenderà a una composizione delle 14 leggi di Core.

  writeFile : Path → Content → FS → FS
  writeFile p c fs = fs ∪ ⌊ (p , c) ⌋

  readFile : Path → FS → FS
  readFile p fs = fs ∩ pathSlice p

  deleteFile : Path → FS → FS
  deleteFile p fs = fs \\ pathSlice p

  -- ══════════════════════════════════════════════════════════════════
  -- TEOREMI CARATTERIZZANTI
  -- ══════════════════════════════════════════════════════════════════

  -- ── Operazioni su ∅: tutto degenera ─────────────────────────────
  -- Pure trivialità via pattern absurd su ⊥, ma vanno scritte una volta.
  -- writeFile-∅ è già non-banale: usa ∪-identityˡ direttamente.
  writeFile-∅ : ∀ p c → writeFile p c ∅ ≈ ⌊ (p , c) ⌋
  writeFile-∅ p c = ∪-identityˡ ⌊ (p , c) ⌋

  readFile-∅ : ∀ p → readFile p ∅ ≈ ∅
  readFile-∅ p = record
    { to   = λ { (() , _) }
    ; from = λ ()
    }

  deleteFile-∅ : ∀ p → deleteFile p ∅ ≈ ∅
  deleteFile-∅ p = record
    { to   = λ { (() , _) }
    ; from = λ ()
    }

  -- ── Read after write, stesso path ───────────────────────────────
  -- La formulazione *onesta* in semantica multivaluata (Plan 9-style):
  -- leggere a `p` dopo aver scritto `(p,c)` produce ciò che c'era prima
  -- a `p` UNITO con il nuovo `(p,c)`. NON è sovrascrittura nucleare:
  -- è layering. La sovrascrittura POSIX vive in overwriteFile.
  readFile-writeFile-same : ∀ p c fs
                          → readFile p (writeFile p c fs)
                          ≈ (readFile p fs ∪ ⌊ (p , c) ⌋)
  readFile-writeFile-same p c fs = record { to = fwd ; from = bwd }
    where
      fwd : ∀ {e} → ((fs ∪ ⌊ (p , c) ⌋) ∩ pathSlice p) e
                  → ((fs ∩ pathSlice p) ∪ ⌊ (p , c) ⌋) e
      fwd (inj₁ x , slice)     = inj₁ (x , slice)
      fwd (inj₂ singleton , _) = inj₂ singleton

      bwd : ∀ {e} → ((fs ∩ pathSlice p) ∪ ⌊ (p , c) ⌋) e
                  → ((fs ∪ ⌊ (p , c) ⌋) ∩ pathSlice p) e
      bwd (inj₁ (x , slice)) = inj₁ x , slice
      bwd (inj₂ singleton)   = inj₂ singleton , proj₁ singleton

  -- ── Read after write, path DIVERSO ──────────────────────────────
  -- L'invariante che fa di IbisFS un *namespace* e non un blob di
  -- pairs: scritture e letture a path diversi NON si vedono. La
  -- contraddizione tra p₁ ≡ p' (slice) e p₁ ≢ p₂ con p₂ ≡ p' (singolet.)
  -- la chiude `⊥-elim` via transitività + simmetria.
  readFile-writeFile-diff : ∀ p₁ p₂ c fs → p₁ ≢ p₂
                          → readFile p₁ (writeFile p₂ c fs)
                          ≈ readFile p₁ fs
  readFile-writeFile-diff p₁ p₂ c fs p₁≢p₂ = record { to = fwd ; from = bwd }
    where
      fwd : ∀ {e} → ((fs ∪ ⌊ (p₂ , c) ⌋) ∩ pathSlice p₁) e
                  → (fs ∩ pathSlice p₁) e
      fwd (inj₁ x , slice)            = x , slice
      fwd (inj₂ (p₂≡p' , _) , p₁≡p')  = ⊥-elim (p₁≢p₂ (trans p₁≡p' (sym p₂≡p')))

      bwd : ∀ {e} → (fs ∩ pathSlice p₁) e
                  → ((fs ∪ ⌊ (p₂ , c) ⌋) ∩ pathSlice p₁) e
      bwd (x , slice) = inj₁ x , slice

  -- ── Delete after write allo stesso path: il delete vince ────────
  -- Tutto ciò che era a `p`, incluso ciò che hai appena scritto, sparisce.
  -- Operativamente: deleteFile è "rimozione di tutto lo slice", non
  -- "rimozione dell'ultima scrittura". È la scelta semantica giusta in
  -- un mondo multivaluato — se ne vuoi una più chirurgica, useremo un
  -- `deleteEntry : Entry → FS → FS` separato in seguito.
  deleteFile-writeFile-same : ∀ p c fs
                            → deleteFile p (writeFile p c fs)
                            ≈ deleteFile p fs
  deleteFile-writeFile-same p c fs = record { to = fwd ; from = bwd }
    where
      fwd : ∀ {e} → ((fs ∪ ⌊ (p , c) ⌋) \\ pathSlice p) e
                  → (fs \\ pathSlice p) e
      fwd (inj₁ x , ¬slice)          = x , ¬slice
      fwd (inj₂ (p≡p' , _) , ¬slice) = ⊥-elim (¬slice p≡p')

      bwd : ∀ {e} → (fs \\ pathSlice p) e
                  → ((fs ∪ ⌊ (p , c) ⌋) \\ pathSlice p) e
      bwd (x , ¬slice) = inj₁ x , ¬slice

  -- ── Delete + write a path DIVERSI: COMMUTANO ─────────────────────
  -- Questo è IL teorema che fa di IbisFS un namespace: delete a `p₁`
  -- e write a `p₂` con `p₁ ≢ p₂` non si vedono fra loro. Senza questo,
  -- "filesystem" sarebbe solo un'unione disordinata di entries.
  -- L'asimmetria: il caso `inj₂` di bwd deve produrre ¬(p₁ ≡ p')
  -- usando l'ipotesi `p₁ ≢ p₂` e `p₂ ≡ p'` (transitività + simmetria).
  deleteFile-writeFile-diff : ∀ p₁ p₂ c fs → p₁ ≢ p₂
                            → deleteFile p₁ (writeFile p₂ c fs)
                            ≈ writeFile p₂ c (deleteFile p₁ fs)
  deleteFile-writeFile-diff p₁ p₂ c fs p₁≢p₂ = record { to = fwd ; from = bwd }
    where
      fwd : ∀ {e} → ((fs ∪ ⌊ (p₂ , c) ⌋) \\ pathSlice p₁) e
                  → ((fs \\ pathSlice p₁) ∪ ⌊ (p₂ , c) ⌋) e
      fwd (inj₁ x , ¬slice)    = inj₁ (x , ¬slice)
      fwd (inj₂ singleton , _) = inj₂ singleton

      bwd : ∀ {e} → ((fs \\ pathSlice p₁) ∪ ⌊ (p₂ , c) ⌋) e
                  → ((fs ∪ ⌊ (p₂ , c) ⌋) \\ pathSlice p₁) e
      bwd (inj₁ (x , ¬slice))            = inj₁ x , ¬slice
      bwd (inj₂ (p₂≡p' , c≡c'))          =
        inj₂ (p₂≡p' , c≡c') , λ p₁≡p' → p₁≢p₂ (trans p₁≡p' (sym p₂≡p'))

  -- ── Delete è idempotente ────────────────────────────────────────
  -- Una seconda cancellazione non ha più nulla da togliere. Pattern
  -- match esplicito sulla coppia annidata + duplicazione del ¬slice.
  deleteFile-idem : ∀ p fs → deleteFile p (deleteFile p fs) ≈ deleteFile p fs
  deleteFile-idem p fs = record
    { to   = proj₁
    ; from = λ w → w , proj₂ w
    }

  -- ── Write è idempotente ─────────────────────────────────────────
  -- Riscrivere lo stesso (p,c) due volte ≈ scriverlo una volta.
  -- Caso d'uso del pagamento: ∪-assoc + ∪-cong + ∪-idem si compongono
  -- via ≈-trans — niente di nuovo da provare, è un corollario gratis.
  writeFile-idem : ∀ p c fs → writeFile p c (writeFile p c fs)
                            ≈ writeFile p c fs
  writeFile-idem p c fs =
    ≈-trans (∪-assoc fs ⌊ (p , c) ⌋ ⌊ (p , c) ⌋)
            (∪-cong ≈-refl (∪-idem ⌊ (p , c) ⌋))

  -- ── Le write commutano SEMPRE ────────────────────────────────────
  -- Anche allo stesso path, perché siamo multivaluati: due write a
  -- (p,c) e (p,c') stackano (∪) e l'ordine non altera il set finale.
  -- Niente ipotesi, niente pattern match: ∪-assoc + ∪-comm + ∪-cong.
  writeFile-comm : ∀ p₁ c₁ p₂ c₂ fs
                 → writeFile p₁ c₁ (writeFile p₂ c₂ fs)
                 ≈ writeFile p₂ c₂ (writeFile p₁ c₁ fs)
  writeFile-comm p₁ c₁ p₂ c₂ fs =
    ≈-trans (∪-assoc fs ⌊ (p₂ , c₂) ⌋ ⌊ (p₁ , c₁) ⌋)
    (≈-trans (∪-cong ≈-refl (∪-comm ⌊ (p₂ , c₂) ⌋ ⌊ (p₁ , c₁) ⌋))
             (≈-sym (∪-assoc fs ⌊ (p₁ , c₁) ⌋ ⌊ (p₂ , c₂) ⌋)))

  -- ══════════════════════════════════════════════════════════════════
  -- OVERWRITE: la semantica "POSIX-like" come scelta esplicita
  -- ══════════════════════════════════════════════════════════════════
  -- writeFile è additivo (layering, Plan 9-style). Per chi vuole la
  -- sovrascrittura nucleare di POSIX la esponiamo come *combinazione*:
  -- prima cancelli tutto a `p`, poi scrivi `(p,c)`. Nessuna primitiva
  -- nuova nel reticolo — solo una sequenza che la libreria nomina.
  --
  -- writeFile e overwriteFile non sono varianti dello stesso operatore
  -- con un flag: sono due *scelte semantiche* distinte, entrambe
  -- dimostrate. Il programmatore (o il runtime) sceglie quale chiamare,
  -- e i teoremi caratterizzanti gli dicono cosa aspettarsi.

  overwriteFile : Path → Content → FS → FS
  overwriteFile p c fs = writeFile p c (deleteFile p fs)

  -- ── HEADLINE: read after overwrite = il singoletto, niente di più ─
  -- L'intera ragione di esistere di overwriteFile è questo teorema.
  -- A differenza di readFile-writeFile (che produce `read precedente
  -- ∪ ⌊(p,c)⌋`), qui il risultato è ESATTAMENTE `⌊(p,c)⌋`: il delete ha
  -- tolto tutto, il write ha aggiunto solo il nuovo. POSIX-style
  -- certificato dal typechecker.
  readFile-overwriteFile : ∀ p c fs
                         → readFile p (overwriteFile p c fs)
                         ≈ ⌊ (p , c) ⌋
  readFile-overwriteFile p c fs = record { to = fwd ; from = bwd }
    where
      fwd : ∀ {e} → readFile p (overwriteFile p c fs) e → ⌊ (p , c) ⌋ e
      fwd (inj₁ (_ , ¬slice) , slice) = ⊥-elim (¬slice slice)
      fwd (inj₂ singleton , _)        = singleton

      bwd : ∀ {e} → ⌊ (p , c) ⌋ e → readFile p (overwriteFile p c fs) e
      bwd singleton = inj₂ singleton , proj₁ singleton

  -- ── Overwrite sul filesystem vuoto = singoletto ──────────────────
  -- Sanity check: la cancellazione su ∅ è no-op (∅ \\ X non ha nulla),
  -- il write fa il resto. Lo verifichiamo direttamente perché il caso
  -- inj₁ è vacuo (⊥ è inabitato).
  overwriteFile-∅ : ∀ p c → overwriteFile p c ∅ ≈ ⌊ (p , c) ⌋
  overwriteFile-∅ p c = record { to = to' ; from = inj₂ }
    where
      to' : ∀ {e} → overwriteFile p c ∅ e → ⌊ (p , c) ⌋ e
      to' (inj₁ (() , _))
      to' (inj₂ singleton) = singleton

  -- ── Overwrite assorbe la write precedente allo stesso path ──────
  -- writeFile poi overwriteFile collassa a solo overwriteFile: la
  -- cancellazione iniziale di overwrite invalida la scrittura
  -- intermedia, qualunque sia il contenuto c' che era stato scritto.
  -- Corollario un-liner: ∪-cong applicato a deleteFile-writeFile-same.
  -- È il primo teorema "interessante" che NON richiede pattern match —
  -- si compone tutto dai mattoni già provati. È il momento in cui il
  -- Core comincia a ripagare il prezzo del setup.
  overwrite-after-write : ∀ p c c' fs
                        → overwriteFile p c (writeFile p c' fs)
                        ≈ overwriteFile p c fs
  overwrite-after-write p c c' fs =
    ∪-cong (deleteFile-writeFile-same p c' fs) ≈-refl

  -- ── Overwrite è idempotente ──────────────────────────────────────
  -- Corollario di deleteFile-writeFile-same + deleteFile-idem,
  -- composti via ∪-cong. Zero pattern match — è la dimostrazione che
  -- la chiusura algebrica del Core/Basic comincia a propagarsi.
  overwriteFile-idem : ∀ p c fs → overwriteFile p c (overwriteFile p c fs)
                                ≈ overwriteFile p c fs
  overwriteFile-idem p c fs =
    ∪-cong (≈-trans (deleteFile-writeFile-same p c (deleteFile p fs))
                    (deleteFile-idem p fs))
           ≈-refl
