# IbisFS

<p align="center">
  <img src="logo.svg" width="180" alt="IbisFS — un ibis sacro col becco curvo nell'acqua, e i tre operatori del reticolo ∪ ∩ \ riflessi sotto"/>
</p>

> *Un filesystem come reticolo, non come gerarchia.*

## L'idea in una frase

**IbisFS è un'algebra per manipolare spazi di nomi: il filesystem è un
reticolo, le operazioni semplici (creare, leggere, cancellare) sono casi
particolari delle operazioni algebriche universali (unione, intersezione,
differenza).**

## La visione

Nei filesystem tradizionali, i percorsi formano un albero. Si parte dai
"file" (foglie) e si costruiscono strutture più complesse (directory,
mount, link). IbisFS rovescia la prospettiva:

> **L'astrazione non è la cima della montagna. È la fondazione.**

La struttura fondamentale di IbisFS è un **reticolo distributivo** i cui
elementi sono *filesystem interi*. Ogni filesystem è un elemento del
reticolo. Le operazioni fondamentali sono:

- **Unione** (`_∪_`): fonde due filesystem
- **Intersezione** (`_∩_`): estrae la parte comune
- **Differenza** (`_\\_`): rimuove un sottospazio (complemento relativo)

Da queste tre operazioni **emergono** tutte le operazioni familiari:

- `writeFile p c`     = `currentFS ∪ ⌊ (p , c) ⌋`
- `readFile p`        = `currentFS ∩ {entries-at p}` poi proiezione
- `deleteFile p`      = `currentFS \\ {entries-at p}`
- `copyDirectory s d` = unione dopo rinominazione
- `merge a b`         = `a ∪ b`
- `diff a b`          = `(a \\ b) ∪ (b \\ a)`

## Stato attuale

`IbisFS.Core` (algebra pura, nessun IO, nessuna dipendenza da Janus)
è chiuso come **reticolo distributivo limitato dal basso**:

| Categoria | Leggi dimostrate |
|---|---|
| `_∪_` come semigruppo commutativo idempotente | `∪-comm`, `∪-assoc`, `∪-idem` |
| `_∩_` come semigruppo commutativo idempotente | `∩-comm`, `∩-assoc`, `∩-idem` |
| Distributività | `∩-∪-distrib`, `∪-∩-distrib` |
| Assorbimento (chiude il reticolo) | `∪-absorbs-∩`, `∩-absorbs-∪` |
| Identità di `_∪_` | `∪-identityˡ`, `∪-identityʳ` |
| Congruenza di `_≈_` | `∪-cong`, `∩-cong` |

**14 teoremi in 185 righe.** Tutto verificato dal typechecker di Agda —
nessun postulato, nessuna extensionality. L'uguaglianza estensionale
`_≈_` è una congruenza setoide costruttiva (andata + ritorno per ogni
entry), non `_≡_` su funzioni.

## Perché Agda

Perché un filesystem non è solo dati, è **comportamento verificato**.
Senza distributività, `readFile p (merge fs₁ fs₂)` non è
necessariamente `readFile p fs₁ ∪ readFile p fs₂` — e Plan 9
union-directory diventerebbe operazionalmente incoerente. In Agda la
distributività non è un commento nella documentazione: è
`∩-∪-distrib`, e il typechecker rifiuta il codice se la rep ne fa
fallire la prova.

## Livelli di astrazione (dalla fondazione alla pratica)

| Livello | Cosa offre | Stato |
|---|---|---|
| `IbisFS.Core` | Il reticolo: `_∪_`, `_∩_`, `_\\_`, `∅`, 14 leggi | ✓ |
| `IbisFS.Basic` | `writeFile`, `readFile`, `deleteFile` derivati | 🚧 |
| `IbisFS.Plan9` | Namespace, `bind`, `mount` come istanze di `∪` | — |
| `IbisFS.Verified` | `Path NotExists → IO Path Exists` via `Janus.Refine` | — |
| `IbisFS.Runtime.POSIX` | Adattatore filesystem reale, sopra Janus | — |
| `IbisFS.Runtime.S3` / `AzureBlob` | Bucket/container come filesystem | — |

L'utente finale non deve conoscere il reticolo. Chiama `writeFile` e
funziona. Ma sotto, `writeFile` è semplicemente un'unione, e tutte le
proprietà sopra valgono *per costruzione*.

## Quick start

### Sviluppare IbisFS

```bash
nix develop                              # Agda 2.8 + stdlib 2.3
agda --library-file=$AGDA_DIR/libraries IbisFS/Laws.agda
# EXIT 0 → le 14 leggi sono verificate
```

### Come libreria (per i consumer)

```nix
inputs.ibisfs.url = "github:avit-io/ibisfs";   # o path:../ibisfs in monorepo
inputs.ibisfs.inputs.nixpkgs.follows = "nixpkgs";

devShells.x86_64-linux.default = inputs.ibisfs.lib.mkShell {
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
};
```

```
# tuo-progetto.agda-lib
name: mio-progetto
include: .
depend: standard-library ibisfs
```

## Roadmap

In ordine di valore, dall'algebra pura al filesystem reale:

1. **`IbisFS.Basic`** — `⌊_⌋ : Entry → FS` (singoletto) + `writeFile`,
   `readFile`, `deleteFile` come *teoremi derivati* del Core. Richiede
   una scelta concreta di `Path` e `Content` con `DecidableEquality`.
   È il salto da "algebra pura" a "API usabile dal programmatore medio".
2. **`IbisFS.Plan9`** — `Path = NonEmpty (List Component)`, `bind` come
   `∪` ristretta, `mount` come unione su sotto-namespace. Le leggi del
   reticolo si traducono in proprietà operazionali di Plan 9
   (commutatività di `bind`, idempotenza di `mount` sullo stesso punto).
   È il *test di realtà* del framing.
3. **`IbisFS.Verified`** — path raffinati: `Path NotExists`,
   `Path Exists`, `Path Readable`. Usa `Janus.Refine` per portare la
   prova fino al sito di chiamata. È dove [Janus](../janus) entra in
   gioco: per la prima volta IbisFS tocca il mondo degli effetti.
4. **`IbisFS.Runtime.POSIX`** — adattatore concreto sopra `Janus.FS`.
   Manda in pensione il PoC che oggi vive *dentro* il repo di Janus.
5. **`IbisFS.Runtime.S3`** e **`IbisFS.Runtime.AzureBlob`** — bucket S3
   e container Azure come filesystem IbisFS. `copyDirectory` da S3 a
   POSIX diventa *un'unica unione tra elementi del reticolo i cui
   runtime sono diversi*. È l'unificazione cloud/locale.

Ordine di esecuzione: (1) sblocca tutto il resto. (2) è validazione
matematica (se Plan 9 non si esprime pulitamente, il framing è
sbagliato). (3)→(4)→(5) è la discesa verso il mondo reale, e dipende
da quanto Janus sarà maturo al momento.

## Connessione con Janus

`IbisFS.Core` non dipende da [Janus](../janus): è algebra pura. La
dipendenza si materializza a partire da `IbisFS.Verified`, dove i path
raffinati hanno bisogno di `Janus.Refine`, e diventa strutturale nei
`Runtime.*`, che usano la "buccia impura" di Janus per parlare con
l'IO Haskell. La separazione di concerns è netta: Janus risolve *come*
attraversare il confine FFI mantenendo le prove; IbisFS risolve *cosa*
trasportare attraverso quel confine.

## Licenza

MIT.
