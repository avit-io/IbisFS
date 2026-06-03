# IbisFS

<p align="center">
  <img src="logo.svg" width="180" alt="IbisFS — un ibis sacro col becco curvo nell'acqua, e i tre operatori del reticolo ∪ ∩ \ riflessi sotto"/>
</p>

> *Un filesystem come reticolo, non come gerarchia.*

## L'idea in una frase

**IbisFS è un'algebra per manipolare spazi di nomi: il filesystem è un
reticolo, le operazioni semplici (creare, leggere, cancellare) sono casi
particolari delle operazioni algebriche universali (unione, intersezione,
differenza). Le proprietà che ti aspetti — commutatività di scritture a
path diversi, idempotenza di delete, identità di scritture vuote — non
sono commenti nella documentazione: sono teoremi verificati da Agda.**

## Demo in 60 secondi

```text
$ nix develop
$ agda --library-file=$AGDA_DIR/libraries --compile --compile-dir=Examples \
       Examples/POSIX.agda
$ ./Examples/POSIX

IbisFS.Runtime.POSIX demo — refined paths + Result al confine

PROMOTE /etc/hostname:
  ↳ esiste (ExistsPath posixFS in mano)
PROMOTE /no/such/path:
  ↳ libero (FreshPath posixFS in mano)

READ /etc/hostname:
  ↳ letto
READ /etc/shadow:
  ↳ errore: EACCES (permessi insufficienti)        ← cattura tipata di IOException
READ /no/such/path:
  ↳ libero, niente da leggere                       ← il typechecker l'aveva già capito
```

```text
$ ./Examples/S3

IbisFS.Runtime.S3 demo — lifecycle su bucket in-memory

[1] promote (atteso libero):              ↳ libero
[2] put (se libero):                       ↳ put OK
[3] promote dopo put (atteso esiste):      ↳ esiste
[4] get (se esiste):                       ↳ get OK | content = "{"answer":42}"
[5] delete (se esiste):                    ↳ delete OK
[6] promote dopo delete (atteso libero):   ↳ libero
```

Quello che vedi:

- **Path raffinati** (`ExistsPath`, `FreshPath`) attraversano il confine
  FFI Agda↔Haskell mantenendo la prova.
- **Result tipati** (`Result FSError`, `Result S3Error`) sostituiscono le
  eccezioni Haskell invisibili: il caller è obbligato dal typechecker a
  pattern-matchare entrambi i casi.
- **Lo stesso codice IbisFS** (`ExistsPath`, `promote-IO`, `getObject-IO`)
  funziona uguale per filesystem POSIX e per object store cloud-shaped.

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

```
writeFile p c     ≡  currentFS ∪ ⌊ (p , c) ⌋
readFile p        ≡  currentFS ∩ pathSlice p     (poi proiezione)
deleteFile p      ≡  currentFS \\ pathSlice p
overwriteFile p c ≡  writeFile p c (deleteFile p currentFS)
copyDirectory s d ≡  unione dopo rinominazione
merge a b         ≡  a ∪ b
diff a b          ≡  (a \\ b) ∪ (b \\ a)
```

## Architettura: sette strati, un'unica narrativa

```
┌────────────────────────────────────────────────────────────────┐
│  Examples/                                                      │
│   POSIX.agda    lifecycle locale (read /etc, gestione EACCES)   │
│   S3.agda       lifecycle cloud (put/get/delete, in-memory)     │
└──────┬─────────────────────────────────────────────────────────┘
       │
┌──────▼─────────────────────────────────────────────────────────┐
│  IbisFS.Runtime.POSIX     │   IbisFS.Runtime.S3                 │
│  rawDoesFileExist (FFI)   │   rawHeadObject (FFI)               │
│  guarded + FSError        │   IORef Map + S3Error               │
│  posixFS : FS  postulato  │   s3FS : FS  postulato              │
│  TRUST BOUNDARY UNICO     │   TRUST BOUNDARY UNICO              │
└──────┬─────────────────────────────┬───────────────────────────┘
       │ refined paths               │ refined paths
┌──────▼─────────────────────────────▼───────────────────────────┐
│  IbisFS.Runtime.Result    (Result E A, condiviso fra runtime)  │
└──────┬─────────────────────────────────────────────────────────┘
       │
┌──────▼─────────────────────────────────────────────────────────┐
│  IbisFS.Verified                                                │
│   Exists, NotExists       (predicati semantici)                 │
│   ExistsPath, FreshPath   (path raffinati = Σ Path P)           │
│   existsRefine            (ponte → Janus.Refine)                │
│   promote, writeFile-fresh, readFile-existing                   │
│   teoremi:  writeFile-creates,  fresh→exists                    │
└──────┬─────────────────────────────────────────────────────────┘
       │  open Janus.Refine
┌──────▼─────────────────────────────────────────────────────────┐
│  Janus.Refine             (Σ A P + validate decidibile)         │
│  Janus.Transport          (encode/decode round-trip)            │
│  Janus.FFI                (call, callChecked)                   │
└────────────────────────────────────────────────────────────────┘
       │
┌──────▼─────────────────────────────────────────────────────────┐
│  IbisFS.Plan9                                                   │
│   Path = List⁺ Component  (istanza concreta del reticolo)       │
│   bind = writeFile, mount = overwriteFile, unmount = deleteFile │
│   bind-commutes, mount-after-bind, read-after-mount             │
└──────┬─────────────────────────────────────────────────────────┘
       │
┌──────▼─────────────────────────────────────────────────────────┐
│  IbisFS.Basic                                                   │
│   ⌊_⌋ singoletto, pathSlice                                     │
│   writeFile, readFile, deleteFile, overwriteFile                │
│   15 teoremi caratterizzanti (read-after-write, write-comm, …)  │
└──────┬─────────────────────────────────────────────────────────┘
       │
┌──────▼─────────────────────────────────────────────────────────┐
│  IbisFS.Laws                                                    │
│   ∪/∩-comm, ∪/∩-assoc, ∪/∩-idem                                 │
│   ∩-∪-distrib, ∪-∩-distrib                                      │
│   ∪-identityˡ/ʳ, ∪/∩-cong, ∪-absorbs-∩, ∩-absorbs-∪             │
│   14 leggi → reticolo distributivo limitato dal basso           │
└──────┬─────────────────────────────────────────────────────────┘
       │
┌──────▼─────────────────────────────────────────────────────────┐
│  IbisFS.Core                                                    │
│   FS = (Path × Content) → Set        ← la rappresentazione (2)  │
│   ∅, _∪_, _∩_, _\\_, _≈_              ← l'algebra               │
└────────────────────────────────────────────────────────────────┘
```

La storia è una sola: **ciò che è dimostrato in Core sopravvive intatto
fino al binario eseguibile**. Niente postulati nascosti lungo la strada.
L'unico trust boundary è il bordo FFI (POSIX o S3), e lì la fiducia è
esplicitamente nominata in due postulati per modulo runtime.

## Lo stato attuale

Tutti i moduli typeckeckano e i due esempi compilano + girano. **Niente
postulati non documentati, niente extensionality, niente assiomi extra.**

| Modulo | Righe | Cosa dimostra |
|---|---:|---|
| `IbisFS.Core` | 79 | la rappresentazione (2) e i costruttori dell'algebra |
| `IbisFS.Laws` | 185 | 14 leggi → reticolo distributivo limitato dal basso |
| `IbisFS.Basic` | 252 | 15 teoremi caratterizzanti dell'API CRUD derivata |
| `IbisFS.Plan9` | 129 | istanza con `Path = List⁺ Component`, 4 teoremi ereditati |
| `IbisFS.Verified` | 151 | path raffinati via `Janus.Refine`, teoremi di propagazione |
| `IbisFS.Runtime.Result` | 23 | `Result E A` condiviso tra i runtime |
| `IbisFS.Runtime.POSIX` | 184 | bridge POSIX, `Result FSError`, FFI con guarded catch |
| `IbisFS.Runtime.S3` | 174 | bridge S3 in-memory, `Result S3Error`, swappabile per amazonka |
| **Examples/POSIX.agda** | 59 | demo eseguibile: read da `/etc/*`, cattura EACCES |
| **Examples/S3.agda** | 96 | demo eseguibile: lifecycle put/get/delete |

Totale codice IbisFS: ~1180 righe. Dipendenza esterna: Janus (~140 righe).

### Le 22 leggi e teoremi di Core + Basic

`IbisFS.Core` + `IbisFS.Laws` chiudono come **reticolo distributivo limitato
dal basso** (l'unica cosa che manca per essere Boolean è il complemento
assoluto, che escludiamo deliberatamente — vorrebbe un "filesystem
universale" che non è rappresentabile in modo finito):

| Categoria | Leggi dimostrate |
|---|---|
| `_∪_` come semigruppo commutativo idempotente | `∪-comm`, `∪-assoc`, `∪-idem` |
| `_∩_` come semigruppo commutativo idempotente | `∩-comm`, `∩-assoc`, `∩-idem` |
| Distributività | `∩-∪-distrib`, `∪-∩-distrib` |
| Assorbimento (chiude il reticolo) | `∪-absorbs-∩`, `∩-absorbs-∪` |
| Identità di `_∪_` | `∪-identityˡ`, `∪-identityʳ` |
| Congruenza setoidale | `∪-cong`, `∩-cong` |

`IbisFS.Basic` ne deriva 15 teoremi caratterizzanti dell'API CRUD:

| | `writeFile` | `readFile` | `deleteFile` | `overwriteFile` |
|---|---|---|---|---|
| **su ∅** | `writeFile-∅` | `readFile-∅` | `deleteFile-∅` | `overwriteFile-∅` |
| **idempotenza** | `writeFile-idem` | — | `deleteFile-idem` | `overwriteFile-idem` |
| **stesso path** | `writeFile-idem` | `readFile-writeFile-same` | `deleteFile-writeFile-same` | `readFile-overwriteFile`, `overwrite-after-write` |
| **path diversi** | `writeFile-comm` | `readFile-writeFile-diff` (`p₁ ≢ p₂`) | `deleteFile-writeFile-diff` (`p₁ ≢ p₂`) | — |

> `deleteFile-writeFile-diff` è il teorema che fa di IbisFS un *namespace*
> e non un blob di pairs: scritture e cancellazioni a path diversi
> **commutano**. Senza, "filesystem" sarebbe solo un'unione disordinata.

`IbisFS.Plan9` istanzia il tutto su `Path = List⁺ Component` e ne ricava
4 teoremi gratis (`bind-commutes`, `bind-idem`, `mount-after-bind`,
`read-after-mount`) — la giustificazione formale delle union directories
di Plan 9, che la documentazione storica menziona ma non dimostra.

`IbisFS.Verified` chiude il cerchio: prende ogni teorema dimostrato sopra
e li *propaga attraverso operazioni di mutazione* via tipi raffinati.

## Perché Agda

Perché un filesystem non è solo dati, è **comportamento verificato**.
Senza distributività, `readFile p (merge fs₁ fs₂)` non è
necessariamente `readFile p fs₁ ∪ readFile p fs₂` — e Plan 9
union-directory diventerebbe operazionalmente incoerente. In Agda la
distributività non è un commento nella documentazione: è
`∩-∪-distrib`, e il typechecker rifiuta il codice se la rappresentazione
ne fa fallire la prova.

Un esempio concreto del payoff. La prova di `read-after-write` in `Basic`:

```agda
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
```

L'intera dimostrazione sono otto righe di pattern match sulle somme e i
prodotti che la rappresentazione (2) produce. Niente magia, niente
assiomi. Il typechecker verifica che il roundtrip andata/ritorno copre
tutti i casi.

Più in alto la storia paga ancora di più. `overwriteFile-idem` in `Basic`:

```agda
overwriteFile-idem : ∀ p c fs → overwriteFile p c (overwriteFile p c fs)
                              ≈ overwriteFile p c fs
overwriteFile-idem p c fs =
  ∪-cong (≈-trans (deleteFile-writeFile-same p c (deleteFile p fs))
                  (deleteFile-idem p fs))
         ≈-refl
```

**Tre righe, zero pattern match.** È composizione pura di tre teoremi
precedenti (`deleteFile-writeFile-same` + `deleteFile-idem` + `∪-cong`).
È il momento in cui il Core inizia a ripagare il prezzo del setup.

## Esempi

`Examples/` contiene due demo eseguibili end-to-end che mostrano
l'integrazione completa: refined types in Agda + Result tipato al
confine FFI + effetti reali.

### `Examples/POSIX.agda`

Lifecycle di `promote → read`, gestendo i tre casi:
- path che esiste ed è leggibile (`/etc/hostname`) → `ok content`
- path che esiste ma non è leggibile (`/etc/shadow`) → `err permissionDenied`
- path che non esiste (`/no/such/path`) → classificato come `FreshPath`,
  niente read

```bash
agda --library-file=$AGDA_DIR/libraries --compile --compile-dir=Examples \
     Examples/POSIX.agda
./Examples/POSIX
```

### `Examples/S3.agda`

Lifecycle completo su un bucket S3 simulato in-memory:
`promote (libero) → put → promote (esiste) → get → delete → promote (libero)`.

Lo stato è mantenuto in un `IORef (Map T.Text T.Text)` lato Haskell, e
attraversa il confine FFI sei volte mediato dai tipi raffinati Agda.

```bash
agda --library-file=$AGDA_DIR/libraries --compile --compile-dir=Examples \
     Examples/S3.agda
./Examples/S3
```

In produzione si sostituisce il blocco `FOREIGN GHC` di
`IbisFS.Runtime.S3` con chiamate `amazonka.S3.{headObject,getObject,
putObject,deleteObject}`. **L'API Agda di sopra non cambia di una riga.**

## Quick start

### Sviluppare IbisFS

```bash
nix develop                              # Agda 2.8 + stdlib 2.3 + Janus + GHC 9.10
agda --library-file=$AGDA_DIR/libraries IbisFS/Runtime/POSIX.agda
# EXIT 0 → tutti i moduli e teoremi verificati
```

### Eseguire i demo

```bash
agda --library-file=$AGDA_DIR/libraries --compile --compile-dir=Examples \
     Examples/POSIX.agda
./Examples/POSIX

agda --library-file=$AGDA_DIR/libraries --compile --compile-dir=Examples \
     Examples/S3.agda
./Examples/S3
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

## Connessione con Janus (struttura, non solo testo)

`IbisFS.Verified` importa `Janus.Transport` e `Janus.Refine`. Non è una
nota nella documentazione: è una `open import` che il typechecker deve
risolvere. La transcript di compilazione dei nostri esempi mostra la
catena reale:

```
Checking IbisFS.Verified (...)
 Checking Janus.Transport (...)
 Checking Janus.Refine    (...)
Checking IbisFS.Runtime.POSIX (...)
Checking Examples.POSIX  (...)
Linking Examples/POSIX
```

Il legame strutturale è qui:

```agda
-- in IbisFS.Verified
existsRefine : (fs : FS)
             → ((p : Path) → Dec (Exists fs p))
             → Refine Path Path             -- ← QUESTO è Janus.Refine
existsRefine fs dec = record
  { transport = idT
  ; P         = Exists fs
  ; validate  = dec
  }
```

Il `Refine Path Path` che produce `Verified` è **lo stesso oggetto** che
`Janus.callChecked` userà al confine FFI quando vorrai validare un valore
ritornato da Haskell. Cambia solo il `transport` (da `idT` a un transport
non banale): la `P` e il `validate` restano costanti dall'algebra fino
al runtime.

Riassumendo:
- **Janus risolve *come* attraversare il confine FFI mantenendo le prove.**
- **IbisFS risolve *cosa* trasportare attraverso quel confine.**

## Cosa NON è IbisFS oggi

Pulizia di aspettative — la libreria è un PoC consolidato, non un drop-in
replacement per `System.Directory`.

- **Non c'è modello dello stato mutabile in Agda.** `posixFS` e `s3FS`
  sono postulati *statici*: dopo un `writeFile-IO`, il filesystem reale è
  cambiato ma il termine Agda no. La prova `ExistsPath posixFS p`
  rispecchia lo stato *al momento del check*, non l'attuale. Per modellare
  la mutazione servirebbe un indice "world" (state-style). Materiale per
  un'iterazione successiva.
- **TOCTOU non eliminato.** Tra `promote-IO` e l'operazione successiva,
  un altro processo può modificare il filesystem. Il `Result` lo gestisce
  esplicitamente (è il motivo per cui ogni read/write può ritornare `err`).
  La prova *limita* il "perché" del fallimento ma non lo elimina.
- **`Path = String` piatto.** Il modello strutturato di Plan 9 esiste
  (`IbisFS.Plan9` con `Path = List⁺ Component`) ma i Runtime usano la
  versione piatta. Il `Transport` `List⁺ Component → String` di join/split
  è un delta puramente algebrico — non ancora scritto.
- **`Content = String`.** In produzione vorremo `ByteString`. Cambio
  banale, non ancora fatto.
- **S3 simulato.** `IbisFS.Runtime.S3` usa un `IORef (Map T.Text T.Text)`
  in Haskell, non amazonka. È in attesa di un bucket reale per giustificare
  l'aggiunta della dep AWS al flake.
- **Niente Azure Blob.** Storicamente nella roadmap, niente codice.
- **`IbisFS.Plan9.Tree`** (il `bind` di directory col prefisso) non c'è.
  È materiale algebrico puro — niente Janus, niente IO. Aggiungerà
  combinatori sopra il reticolo.

Tutto il resto — *l'algebra del reticolo, i teoremi del CRUD, i path
raffinati, il bridge FFI tipato* — funziona ed è dimostrato dal
typechecker.

## Pedagogia: in che ordine leggerlo

Per un lettore nuovo a Agda o ai reticoli:

1. **`IbisFS/Core.agda`** (79 righe). La rappresentazione (2) +
   le operazioni del reticolo. Capisci `FS = Entry → Set` e tutto
   il resto cade in posto.
2. **Lo schema delle leggi** in `IbisFS/Laws.agda`. Le tre direzioni
   (commutatività, associatività, idempotenza) di `_∪_` valgono perché
   sono isomorfismi banali sui tipi somma. Le altre 11 leggi sono nello
   stesso stampo.
3. **`IbisFS/Basic.agda`** fino al teorema `writeFile-idem`. Vedi come
   un'API CRUD nasce come *zucchero* sopra l'algebra del reticolo. I
   teoremi caratterizzanti sono corollari.
4. **`IbisFS/Plan9.agda`**. Capisci come una istanza concreta del
   reticolo guadagna semantica operativa senza riscrivere niente. Le
   union directories di Plan 9 sono `_∪_`, punto.
5. **`IbisFS/Verified.agda`**. Il punto in cui i tipi raffinati entrano
   in gioco. `ExistsPath`, `FreshPath`. La conessione con Janus.Refine.
6. **`IbisFS/Runtime/POSIX.agda` + `Examples/POSIX.agda`**. Il momento in
   cui tutto tocca il mondo reale via FFI. Trust boundary esplicito;
   tutto il resto rimane dimostrato.

Tempi indicativi (Agda intermedio): 2–4 ore per leggere tutto e
comprendere il pattern. Aggiungere o modificare un teorema: ~15 minuti.

## Roadmap

In ordine di valore concreto, dalla pulizia al cloud reale:

1. **`Content = ByteString`** per i runtime. Banale, da fare prima della
   produzione: switch su `Data.ByteString.UTF8` in Haskell e un binding
   Agda minimo.
2. **`IbisFS.Plan9.Tree`** — `bind` di directory col prefisso, `_≼_`
   relazione di prefisso, strip + concat dei suffissi. Algebra pura,
   niente Janus. Completa il modello Plan 9.
3. **amazonka su S3** — sostituisci il blocco `FOREIGN GHC` di
   `Runtime.S3` con `amazonka-s3`. L'API Agda resta congelata. Richiede
   `amazonka-s3` come Haskell dep nel flake (pesante in build, sostenibile).
4. **`IbisFS.Runtime.AzureBlob`** — stesso shape di `Runtime.S3`. Container
   come bucket, blob come key. Chiude la promessa "due cloud" del progetto
   originale.
5. **Modello dello stato mutabile** — index `posixFS`/`s3FS` per un
   parametro "world" che cambia dopo ogni mutazione. Cambia il codice
   cliente, va pianificato come breaking change.

## Licenza

MIT.
