module IbisFS.Runtime.POSIX where

open import IbisFS.Core
open import IbisFS.Basic
open import IbisFS.Verified
open import Janus.FFI using (_>>=_; return)
open import Agda.Builtin.IO using (IO)
open import Agda.Builtin.String using (String)
open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Unit using (⊤)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Product using (_,_; proj₁)

-- IbisFS.Runtime.POSIX è l'adattatore tra il modello di IbisFS.Verified
-- (path raffinati, prove statiche) e il filesystem POSIX reale via FFI
-- Haskell. Il primo modulo dell'ecosistema che genera EFFETTI veri.
--
-- Architettura:
--   ┌──────────────────────────────────────────────────────────┐
--   │  IbisFS.Verified.ExistsPath / FreshPath (Σ Path P)        │
--   │                          ↑                                │
--   │                          │  promote-IO   (bridge)         │
--   │                          ↓                                │
--   │  POSTULATI:   posixFS : FS                                │
--   │               posix-witness : (p)(b) → boolWitness p b    │
--   │                          ↑                                │
--   │                          │  ← TRUST BOUNDARY (unico)      │
--   │                          ↓                                │
--   │  rawDoesFileExist : String → IO Bool                      │
--   │  rawReadFile      : String → IO (Result FSError String)   │
--   │  rawWriteFile/Remove                                      │
--   │  (FOREIGN GHC: System.Directory + guarded exception catch)│
--   └──────────────────────────────────────────────────────────┘
--
-- Niente split Safe/unsafe: questo È il POSIX. Le operazioni che
-- possono fallire ritornano Result, le eccezioni Haskell sono catturate
-- al confine e tradotte in dati tipati Agda.

-- ══════════════════════════════════════════════════════════════════
-- LE SCELTE CONCRETE DEL RUNTIME POSIX
-- ══════════════════════════════════════════════════════════════════
-- Path = FilePath = String (piatto). In una versione successiva
-- esporremo `Plan9.Path = List⁺ Component` e useremo un Janus.Transport
-- per fare il join/split — quello è un delta puro algebrico, non
-- tocca questo modulo runtime.

Path : Set
Path = String

-- Content = String per il PoC (è la scelta che Data.Text.IO rende più
-- diretta in Haskell). Versione produzione: ByteString.
Content : Set
Content = String

-- Istanziamo IbisFS.{Core,Basic,Verified} con questi concreti.
-- `public` re-esporta tutto: i consumer di Runtime.POSIX vedono
-- direttamente FS, ExistsPath, FreshPath, ecc. con Path = String fissato.
open Lattice  Path Content public
open Basic    Path Content public
open Verified Path Content public

-- ══════════════════════════════════════════════════════════════════
-- TASSONOMIA DEGLI ERRORI POSIX
-- ══════════════════════════════════════════════════════════════════
-- Le eccezioni Haskell sono INVISIBILI nel tipo `IO a`. Qui le rendiamo
-- dati di prima classe: niente più "speriamo che non lanci". Tre
-- categorie ESPLICITE + un catch-all tipato. La traduzione eccezione
-- → costruttore avviene UNA VOLTA al confine FFI, in Haskell.

data FSError : Set where
  doesNotExist     : FSError
  permissionDenied : FSError
  otherFSError     : String → FSError

-- Result E A: o un errore, o un valore. È il tipo che spinge il caller
-- a ragionare esplicitamente sul caso di fallimento — niente più
-- eccezioni runtime non gestite.
data Result (E A : Set) : Set where
  err : E → Result E A
  ok  : A → Result E A

-- ══════════════════════════════════════════════════════════════════
-- LA "BUCCIA IMPURA": System.Directory + Data.Text.IO, GUARDED
-- ══════════════════════════════════════════════════════════════════
-- Il FOREIGN GHC blocco è il SOLO punto del modulo dove vive Haskell.
-- `guarded` cattura System.IO.Error e produce un Result tipato. Da qui
-- in giù il consumer Agda non vede mai `IOException`.

{-# FOREIGN GHC import qualified System.Directory as D #-}
{-# FOREIGN GHC import qualified Data.Text as T #-}
{-# FOREIGN GHC import qualified Data.Text.IO as TIO #-}
{-# FOREIGN GHC import qualified Control.Exception as E #-}
{-# FOREIGN GHC import System.IO.Error (isDoesNotExistError, isPermissionError) #-}
{-# FOREIGN GHC
data FSError = ENOENT | EACCES | OtherFSError T.Text
data Result e a = Err e | Ok a

guarded :: IO a -> IO (Result FSError a)
guarded act = E.catch (Ok <$> act) handler
  where
    handler :: E.IOException -> IO (Result FSError a)
    handler e
      | isDoesNotExistError e = pure (Err ENOENT)
      | isPermissionError  e  = pure (Err EACCES)
      | otherwise             = pure (Err (OtherFSError (T.pack (show e))))
#-}

{-# COMPILE GHC FSError = data FSError (ENOENT | EACCES | OtherFSError) #-}
{-# COMPILE GHC Result  = data Result  (Err | Ok) #-}

postulate
  rawDoesFileExist : String → IO Bool
  rawReadFile      : String → IO (Result FSError String)
  rawWriteFile     : String → String → IO (Result FSError ⊤)
  rawRemoveFile    : String → IO (Result FSError ⊤)

{-# COMPILE GHC rawDoesFileExist = D.doesFileExist . T.unpack #-}
{-# COMPILE GHC rawReadFile      = guarded . TIO.readFile . T.unpack #-}
{-# COMPILE GHC rawWriteFile     = \p c -> guarded (TIO.writeFile (T.unpack p) c) #-}
{-# COMPILE GHC rawRemoveFile    = guarded . D.removeFile . T.unpack #-}

-- ══════════════════════════════════════════════════════════════════
-- IL FILESYSTEM POSIX COME OGGETTO ASTRATTO
-- ══════════════════════════════════════════════════════════════════
-- Postuliamo l'esistenza di un FS che RAPPRESENTA lo stato corrente
-- del filesystem POSIX al momento delle chiamate. È il *trust boundary*
-- tra mondo Agda dimostrato e mondo runtime non-dimostrabile.
--
-- LIMITAZIONE NOTA: `posixFS` è statico in Agda. Dopo un writeFile-IO
-- il filesystem reale cambia, ma `posixFS` non lo riflette — qualunque
-- ExistsPath/FreshPath prodotto prima resta nei tipi, ma il suo
-- significato semantico è "vero al momento del check". TOCTOU: tra
-- promote-IO e una operazione successiva un altro processo può
-- modificare lo stato. La Result handling sotto è ciò che rende
-- l'API onesta su questo: ogni read/write può fallire e DEVE essere
-- gestito esplicitamente dal caller.
--
-- Per modellare la mutazione formalmente servirebbe un FS indicizzato
-- da un parametro "world" (state-style indexing). Materiale per una
-- versione futura: la storia "Verified" attuale non lo richiede.
postulate
  posixFS : FS

-- ══════════════════════════════════════════════════════════════════
-- IL CONTRATTO FFI: dal Bool runtime al witness Agda
-- ══════════════════════════════════════════════════════════════════
boolWitness : (p : Path) → Bool → Set
boolWitness p true  = Exists posixFS p
boolWitness p false = NotExists posixFS p

-- Il postulato che traduce il risultato di rawDoesFileExist in prova
-- Agda. Nessuna COMPILE GHC: a runtime una sua occorrenza diventa
-- `undefined` in Haskell — ma non viene mai FORZATA perché i nostri
-- usi sono solo in posizione di prova (mai destrutturate nel codice IO).
-- Pattern classico di proof-irrelevance: il witness esiste per il
-- typechecker, è un nessuno a runtime.
postulate
  posix-witness : (p : Path) (b : Bool) → boolWitness p b

-- ══════════════════════════════════════════════════════════════════
-- promote-IO: il BRIDGE tra IO Bool e tipi raffinati
-- ══════════════════════════════════════════════════════════════════
-- Non ha Result perché doesFileExist è totale: ritorna sempre o true
-- o false. Niente eccezioni possibili a questo livello (un path
-- inaccessibile per permessi parents → false, gestito dal runtime).
promote-IO : (p : Path) → IO (ExistsPath posixFS ⊎ FreshPath posixFS)
promote-IO p = rawDoesFileExist p >>= go
  where
    go : Bool → IO (ExistsPath posixFS ⊎ FreshPath posixFS)
    go true  = return (inj₁ (p , posix-witness p true))
    go false = return (inj₂ (p , posix-witness p false))

-- ══════════════════════════════════════════════════════════════════
-- API RAFFINATA con effetti POSIX reali, Result-tipata
-- ══════════════════════════════════════════════════════════════════
-- Queste sono le operazioni che il consumatore IbisFS chiama. Non
-- accettano un Path raw — accettano un *path con prova*. Il typechecker
-- impone la prova; il runtime esegue l'effetto E gestisce le eccezioni.
-- Il caller è OBBLIGATO a pattern-matchare il Result — niente più
-- "ho dimenticato che readFile può lanciare".

readFile-IO : ExistsPath posixFS → IO (Result FSError Content)
readFile-IO (p , _) = rawReadFile p

writeFile-fresh-IO : FreshPath posixFS → Content → IO (Result FSError ⊤)
writeFile-fresh-IO (p , _) c = rawWriteFile p c

removeFile-IO : ExistsPath posixFS → IO (Result FSError ⊤)
removeFile-IO (p , _) = rawRemoveFile p
