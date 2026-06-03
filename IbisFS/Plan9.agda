module IbisFS.Plan9 where

open import IbisFS.Core
open import IbisFS.Laws
open import IbisFS.Basic
open import Data.List.NonEmpty using (List⁺)
open import Data.Product using (_,_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

-- IbisFS.Plan9 è il *test di realtà* del framing: se il modello di
-- Plan 9 (namespace come reticolo di bind, union directories, mount
-- come replace) si esprime pulitamente sopra IbisFS.Core, allora la
-- scelta della rappresentazione (2) era quella giusta. Se rompiamo
-- qualcosa qui, è meglio scoprirlo prima di accumulare API derivata.
--
-- Component e Content restano parametri: l'algebra di Plan 9 non
-- dipende dal fatto che i componenti siano string, bytes, o token
-- crittografici (per i 9p fileserver moderni). Le scelte concrete
-- vivono nei runtime.
module Plan9 (Component Content : Set) where

  -- ── la scelta di Path ─────────────────────────────────────────────
  -- "/foo/bar"  → foo ∷⁺ bar ∷ []   (List⁺ è non-empty per costruzione:
  -- un path Plan 9 ha sempre almeno un componente, non c'è "il path
  -- vuoto" senza il root contesto).
  Path : Set
  Path = List⁺ Component

  -- ══════════════════════════════════════════════════════════════════
  -- IL PASSO CHE VALIDA TUTTO IL DESIGN
  -- ══════════════════════════════════════════════════════════════════
  -- Le 14 leggi di Lattice + i teoremi di Basic specializzano a
  -- Path = List⁺ Component senza UNA SOLA RIGA di lavoro nuova. È la
  -- parametricità che paga il suo prezzo: non rifacciamo, ereditiamo.
  open Lattice Path Content public
  open Laws    Path Content public
  open Basic   Path Content public

  -- ══════════════════════════════════════════════════════════════════
  -- LE OPERAZIONI PLAN 9 = nomi sopra il reticolo
  -- ══════════════════════════════════════════════════════════════════
  -- Plan 9 ha tre modi di binding (dalla bind(2) e namespace(4)):
  --   bind -b src dst  → src va PRIMA  di dst nel lookup (stack avanti)
  --   bind -a src dst  → src va DOPO   di dst nel lookup (stack dietro)
  --   bind    src dst  → REPLACE: dst nascosto, vede solo src
  --
  -- Nel nostro modello multivaluato, l'ORDINE di lookup è una scelta
  -- del runtime (proiezione su un ∪), non dell'algebra. Quindi -b e
  -- -a coincidono qui: entrambi sono unione, semanticamente uguali a
  -- livello di SET di contenuti visibili. Il default replace è invece
  -- una scelta semantica diversa: ⇒ overwriteFile.

  -- bind (-a, -b): la risorsa si STACKA, lookup vede l'unione. È
  -- l'operazione che giustifica il modello multivaluato di IbisFS.
  bind : Path → Content → FS → FS
  bind = writeFile

  -- mount (bind default replace): la nuova risorsa SOSTITUISCE tutto
  -- ciò che era al punto di mount. Semantica POSIX-like ereditata.
  mount : Path → Content → FS → FS
  mount = overwriteFile

  unmount : Path → FS → FS
  unmount = deleteFile

  -- ── identità definizionali: nessuna primitiva nuova ──────────────
  -- Questi ≡ refl certificano che bind/mount/unmount NON aggiungono
  -- una capacità nuova al reticolo — sono ribattezzature.
  bind≡writeFile  : ∀ p c ns → bind p c ns  ≡ writeFile p c ns
  mount≡overwrite : ∀ p c ns → mount p c ns ≡ overwriteFile p c ns
  unmount≡delete  : ∀ p ns   → unmount p ns ≡ deleteFile p ns
  bind≡writeFile  _ _ _ = refl
  mount≡overwrite _ _ _ = refl
  unmount≡delete  _ _   = refl

  -- ══════════════════════════════════════════════════════════════════
  -- PROPRIETÀ PLAN 9 EREDITATE
  -- ══════════════════════════════════════════════════════════════════
  -- Queste sono cose che la documentazione di Plan 9 lista come
  -- "ovviamente vere" senza dimostrarle. Qui sono teoremi.

  -- ── I bind commutano ────────────────────────────────────────────
  -- L'ordine di stacking non cambia il SET di contenuti visibili in
  -- lookup. È la giustificazione formale delle union directories di
  -- Plan 9: se due processi fanno `bind A /foo` e `bind B /foo` in
  -- ordine arbitrario, il namespace risultante è lo stesso.
  bind-commutes : ∀ p c c' ns
                → bind p c (bind p c' ns) ≈ bind p c' (bind p c ns)
  bind-commutes p c c' ns =
    ≈-trans (∪-assoc ns ⌊ (p , c') ⌋ ⌊ (p , c) ⌋)
    (≈-trans (∪-cong ≈-refl (∪-comm ⌊ (p , c') ⌋ ⌊ (p , c) ⌋))
             (≈-sym (∪-assoc ns ⌊ (p , c) ⌋ ⌊ (p , c') ⌋)))

  -- ── Lo stesso bind è idempotente ────────────────────────────────
  -- Bindare la stessa risorsa due volte allo stesso path = una volta.
  bind-idem : ∀ p c ns → bind p c (bind p c ns) ≈ bind p c ns
  bind-idem = writeFile-idem

  -- ── mount nasconde i bind precedenti allo stesso path ────────────
  -- È la traduzione dell'invariante Plan 9 "replace mode wins" in
  -- termini algebrici. Letteralmente overwrite-after-write rinominato.
  mount-after-bind : ∀ p c c' ns
                   → mount p c (bind p c' ns) ≈ mount p c ns
  mount-after-bind = overwrite-after-write

  -- ── Read dopo un mount = ciò che hai montato, niente trapelature ─
  -- È la garanzia che un mount con replace non lascia entries
  -- "fantasma" del namespace precedente al punto di mount.
  -- Letteralmente readFile-overwriteFile.
  read-after-mount : ∀ p c ns
                   → readFile p (mount p c ns) ≈ ⌊ (p , c) ⌋
  read-after-mount = readFile-overwriteFile

  -- ══════════════════════════════════════════════════════════════════
  -- LIMITE ATTUALE (e dove andare per superarlo)
  -- ══════════════════════════════════════════════════════════════════
  -- Plan 9 ha un'operazione di bind che NON è ancora qui: il `bind`
  -- "di directory" che rimappa un intero sottoalbero. In termini di
  -- prefissi: bind-tree src dst ns = ns ∪ rebrand(src, dst, ns), dove
  -- `rebrand` riscrive ogni entry (src ++ suffix, c) come (dst ++ suffix, c).
  --
  -- Per esprimerlo ci serve struttura aggiuntiva su Path:
  --   - una relazione di prefisso `_≼_ : Path → Path → Set`
  --   - lo strip del prefisso `strip : src ≼ p → Suffix`
  --   - la concatenazione `_++_ : Path → Suffix → Path`
  --
  -- È materiale per un sotto-modulo `IbisFS.Plan9.Tree` o per
  -- `IbisFS.Plan9.Prefix`. NIENTE di questo richiede toccare Core o
  -- Basic: il reticolo è già adeguato. È solo aggiungere combinatori.
