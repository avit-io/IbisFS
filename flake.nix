{
  description = "IbisFS — un filesystem come reticolo, non come gerarchia";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2511.912939";
    piforge = {
      url  = "github:avit-io/piforge";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # path:../janus non funziona in pure-eval (Nix risolve da /nix/store).
    # Per dev locale usiamo git+file con path assoluto; quando janus sarà
    # pubblicato su GitHub questa riga diventerà "github:avit-io/janus".
    janus = {
      url = "git+file:///home/a.vitturi/personal/janus";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.piforge.follows = "piforge";
    };
  };

  outputs = { self, nixpkgs, piforge, janus }:
    let
      system = "x86_64-linux";
      pkgs   = nixpkgs.legacyPackages.${system};

      # IbisFS.Core/Basic/Plan9 sono algebra pura. IbisFS.Verified
      # dipende da Janus (Janus.Refine come witness packager). Per
      # semplicità il .agda-lib esposto richiede janus sempre —
      # se un consumer volesse solo Core potrebbe ignorare la dep.
      ibisfsLib = pkgs.stdenv.mkDerivation {
        name      = "ibisfs-agda-lib";
        src       = builtins.path { path = ./.; name = "ibisfs-src"; };
        dontBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -r IbisFS $out/
          printf 'name: ibisfs\ninclude: .\ndepend: standard-library janus\n' \
            > $out/ibisfs.agda-lib
        '';
      };

      # Copia scrivibile della libreria ibisfs per i consumer.
      # _stdlib e _jns sono impostati da janus.lib.mkShell tramite il
      # suo shellHook concatenato (copyStdlib + copyJanus).
      copyIbis = ''
        _ibs="$_cache/ibisfs-src"
        if [ ! -d "$_ibs" ]; then
          echo "ibisfs: copying IbisFS library to $_ibs (one-time setup)..." >&2
          mkdir -p "$_ibs"
          cp -r ${ibisfsLib}/. "$_ibs/"
          chmod -R u+w "$_ibs"
          printf 'name: ibisfs\ninclude: .\ndepend: standard-library janus\n' \
            > "$_ibs/ibisfs.agda-lib"
        fi
      '';

    in
    {
      packages.${system} = {
        lib     = ibisfsLib;
        default = ibisfsLib;
      };

      # Sviluppo di ibisfs in-tree: janus.lib.mkShell ci dà stdlib +
      # janus + GHC. Il nostro ibisfs.agda-lib in-tree è trovato per
      # traversal — non serve registrarlo in libraries.
      devShells.${system}.default = janus.lib.mkShell {
        inherit pkgs;
      };

      # API per i consumer downstream: chaina janus.lib.mkShell e
      # aggiunge ibisfs alle libraries. Stdlib + janus + ibisfs in AGDA_DIR.
      lib.mkShell = { pkgs, extraPackages ? [], shellHook ? "" }:
        janus.lib.mkShell {
          inherit pkgs extraPackages;
          shellHook = copyIbis + ''
            mkdir -p "$_cache/ibisfs-lib"
            printf '%s\n%s\n%s\n' \
              "$_stdlib/standard-library.agda-lib" \
              "$_jns/janus.agda-lib" \
              "$_ibs/ibisfs.agda-lib" \
              > "$_cache/ibisfs-lib/libraries"
            export AGDA_DIR="$_cache/ibisfs-lib"
          '' + shellHook;
        };
    };
}
