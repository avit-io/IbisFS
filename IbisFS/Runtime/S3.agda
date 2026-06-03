module IbisFS.Runtime.S3 where

open import IbisFS.Core
open import IbisFS.Basic
open import IbisFS.Verified
open import IbisFS.Runtime.Result using (Result; err; ok) public
open import Janus.FFI using (_>>=_; return)
open import Agda.Builtin.IO using (IO)
open import Agda.Builtin.String using (String)
open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Unit using (⊤)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Product using (_,_; proj₁)

-- IbisFS.Runtime.S3 è il *test di realtà* della libreria. Lo stesso
-- modello di IbisFS.Verified (FS lattice + path raffinati) funziona
-- per object store cloud, non solo per filesystem POSIX. Era la
-- promessa centrale della libreria: "una singola astrazione copre
-- locale + AWS + Azure". Qui la verifichiamo come codice eseguibile.
--
-- Architettura: IDENTICA a IbisFS.Runtime.POSIX. Solo i nomi e la
-- buccia impura cambiano. Il fatto che il refactor sia stato così
-- "copia, rinomina, modifica la buccia" è il pagamento del design.
--   POSIX                       S3
--   posixFS              ↔     s3FS
--   rawDoesFileExist     ↔     rawHeadObject
--   rawReadFile          ↔     rawGetObject
--   rawWriteFile         ↔     rawPutObject
--   rawRemoveFile        ↔     rawDeleteObject
--   readFile-IO          ↔     getObject-IO
--   writeFile-fresh-IO   ↔     putObject-fresh-IO
--   removeFile-IO        ↔     deleteObject-IO
--
-- Implementazione del backend: in-memory simulator per la demo (un
-- IORef di Map T.Text T.Text in Haskell, sotto). Per produzione si
-- sostituisce IL SOLO blocco FOREIGN GHC con chiamate amazonka.S3 —
-- l'API Agda di sopra non cambia di una riga.

-- ══════════════════════════════════════════════════════════════════
-- LE SCELTE CONCRETE DEL RUNTIME S3
-- ══════════════════════════════════════════════════════════════════
-- Path = S3 key (la chiave dentro un bucket implicito). Per ora un
-- bucket per processo; in produzione Path = Bucket × Key.

Path : Set
Path = String

Content : Set
Content = String

open Lattice  Path Content public
open Basic    Path Content public
open Verified Path Content public

-- ══════════════════════════════════════════════════════════════════
-- TASSONOMIA ERRORI S3
-- ══════════════════════════════════════════════════════════════════
-- I codici HTTP di AWS S3 mappano a costruttori distinti:
--   404 → noSuchKey, 403 → accessDenied, 5xx → serviceError,
--   tutto il resto → otherS3Error.
data S3Error : Set where
  noSuchKey    : S3Error
  accessDenied : S3Error
  serviceError : String → S3Error
  otherS3Error : String → S3Error

-- Result viene da IbisFS.Runtime.Result (condiviso con POSIX, Azure Blob, …).

-- ══════════════════════════════════════════════════════════════════
-- LA "BUCCIA IMPURA": S3 in-memory simulator
-- ══════════════════════════════════════════════════════════════════
-- Un IORef di Map T.Text T.Text simula il bucket. Global mutable state
-- via unsafePerformIO + NOINLINE — pattern classico Haskell per stato
-- di processo. NIENTE network qui: il punto della demo è mostrare
-- l'INTEGRAZIONE col modello Verified, non testare amazonka.
--
-- Per produzione: sostituisci IL BODY di queste 4 funzioni Haskell con
-- amazonka.S3.headObject/getObject/putObject/deleteObject. L'API Agda
-- non cambia. Il typechecker di Agda continuerà a forzare gli stessi
-- invarianti sul caller.

{-# FOREIGN GHC import qualified Data.Text as T #-}
{-# FOREIGN GHC import qualified Data.Map.Strict as Map #-}
{-# FOREIGN GHC import Data.IORef #-}
{-# FOREIGN GHC import System.IO.Unsafe (unsafePerformIO) #-}
{-# FOREIGN GHC import qualified MAlonzo.Code.IbisFS.Runtime.Result as RR #-}
{-# FOREIGN GHC
data S3Error = NoSuchKey | AccessDenied | ServiceError T.Text | OtherS3Error T.Text

{-# NOINLINE s3Bucket #-}
s3Bucket :: IORef (Map.Map T.Text T.Text)
s3Bucket = unsafePerformIO (newIORef Map.empty)

s3HeadObject :: T.Text -> IO Bool
s3HeadObject k = Map.member k <$> readIORef s3Bucket

s3GetObject :: T.Text -> IO (RR.Result S3Error T.Text)
s3GetObject k = do
  m <- readIORef s3Bucket
  case Map.lookup k m of
    Just v  -> pure (RR.Ok v)
    Nothing -> pure (RR.Err NoSuchKey)

s3PutObject :: T.Text -> T.Text -> IO (RR.Result S3Error ())
s3PutObject k v = do
  modifyIORef s3Bucket (Map.insert k v)
  pure (RR.Ok ())

-- S3 reale: DELETE su chiave inesistente ritorna 204 (success). Lo
-- specchiamo qui per fedeltà al protocollo.
s3DeleteObject :: T.Text -> IO (RR.Result S3Error ())
s3DeleteObject k = do
  modifyIORef s3Bucket (Map.delete k)
  pure (RR.Ok ())
#-}

{-# COMPILE GHC S3Error = data S3Error (NoSuchKey | AccessDenied | ServiceError | OtherS3Error) #-}

postulate
  rawHeadObject   : String → IO Bool
  rawGetObject    : String → IO (Result S3Error String)
  rawPutObject    : String → String → IO (Result S3Error ⊤)
  rawDeleteObject : String → IO (Result S3Error ⊤)

{-# COMPILE GHC rawHeadObject   = s3HeadObject   #-}
{-# COMPILE GHC rawGetObject    = s3GetObject    #-}
{-# COMPILE GHC rawPutObject    = s3PutObject    #-}
{-# COMPILE GHC rawDeleteObject = s3DeleteObject #-}

-- ══════════════════════════════════════════════════════════════════
-- IL BUCKET S3 COME OGGETTO ASTRATTO
-- ══════════════════════════════════════════════════════════════════
-- Stesso pattern di posixFS: postulato che rappresenta lo stato
-- corrente del bucket al momento delle chiamate. Trust boundary unico.
postulate
  s3FS : FS

boolWitness : (p : Path) → Bool → Set
boolWitness p true  = Exists s3FS p
boolWitness p false = NotExists s3FS p

postulate
  s3-witness : (p : Path) (b : Bool) → boolWitness p b

-- ══════════════════════════════════════════════════════════════════
-- promote-IO: il bridge IO ↔ Refined per S3
-- ══════════════════════════════════════════════════════════════════
-- headObject è la chiamata S3 economica per esistenza (no body). Non
-- ritorna Result perché in produzione le sole eccezioni qui sarebbero
-- network errors o auth — gestite come false per la demo. La versione
-- produzione gestirà gli auth in un layer separato.
promote-IO : (p : Path) → IO (ExistsPath s3FS ⊎ FreshPath s3FS)
promote-IO p = rawHeadObject p >>= go
  where
    go : Bool → IO (ExistsPath s3FS ⊎ FreshPath s3FS)
    go true  = return (inj₁ (p , s3-witness p true))
    go false = return (inj₂ (p , s3-witness p false))

-- ══════════════════════════════════════════════════════════════════
-- API RAFFINATA per S3, Result-tipata
-- ══════════════════════════════════════════════════════════════════
-- Identico shape di POSIX. Il caller passa il path raffinato, riceve
-- un Result. Il typechecker non gli permette di chiamare getObject
-- senza un ExistsPath, e non gli permette di ignorare l'eventuale Err.

getObject-IO : ExistsPath s3FS → IO (Result S3Error Content)
getObject-IO (p , _) = rawGetObject p

putObject-fresh-IO : FreshPath s3FS → Content → IO (Result S3Error ⊤)
putObject-fresh-IO (p , _) c = rawPutObject p c

deleteObject-IO : ExistsPath s3FS → IO (Result S3Error ⊤)
deleteObject-IO (p , _) = rawDeleteObject p
