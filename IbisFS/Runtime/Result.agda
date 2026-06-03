module IbisFS.Runtime.Result where

-- IbisFS.Runtime.Result è il tipo Result condiviso da tutti i runtime
-- (POSIX, S3, Azure Blob, …). Lo definiamo UNA volta sia in Agda che
-- in Haskell, così:
--
--   * Importare due runtime nello stesso modulo non genera conflitti
--     di nome su Result (problema che avevamo con il Result locale).
--   * I FOREIGN GHC dei runtime referenziano lo stesso Haskell `Result`
--     via il MAlonzo qualified name di questo modulo.
--
-- Gli errori specifici (FSError, S3Error, AzureBlobError) restano
-- nei rispettivi runtime: sono tassonomie diverse, non condividono.

data Result (E A : Set) : Set where
  err : E → Result E A
  ok  : A → Result E A

-- Il pattern in entrambi i mondi è: o c'è un errore, o c'è un valore.
-- Lo stesso costruttore-nominato che già usavi in Haskell (Left/Right)
-- ma con etichette che dicono cosa sono nel contesto FS.
{-# FOREIGN GHC data Result e a = Err e | Ok a #-}
{-# COMPILE GHC Result = data Result (Err | Ok) #-}
