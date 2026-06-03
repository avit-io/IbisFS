{
  description = "IbisFS — un filesystem come reticolo, non come gerarchia";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2511.912939";
    piforge = {
      url  = "github:avit-io/piforge";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, piforge }:
    let
      system = "x86_64-linux";
      pkgs   = nixpkgs.legacyPackages.${system};

      # IbisFS.Core è ALGEBRA PURA: niente IO, niente Janus. Solo stdlib.
      # I runtime (POSIX via Janus, S3, Azure) vivranno in moduli/repo separati.
      ibisfsLib = pkgs.stdenv.mkDerivation {
        name      = "ibisfs-agda-lib";
        src       = builtins.path { path = ./.; name = "ibisfs-src"; };
        dontBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -r IbisFS $out/
          printf 'name: ibisfs\ninclude: .\ndepend: standard-library\n' \
            > $out/ibisfs.agda-lib
        '';
      };

      stdlib28 = piforge.packages.${system}."stdlib-28";

      # Agda 2.8 scrive _build/ accanto al .agda-lib più vicino → store EROFS.
      # Stessa strategia di janus / cardea / agdovana.
      copyStdlib = ''
        _cache="''${XDG_CACHE_HOME:-$HOME/.cache}/piforge"
        _stdlib="$_cache/stdlib-2.3"
        if [ ! -d "$_stdlib" ]; then
          echo "ibisfs: copying stdlib 2.3 to $_stdlib (one-time setup)..." >&2
          mkdir -p "$_stdlib"
          cp -r ${stdlib28}/. "$_stdlib/"
          chmod -R u+w "$_stdlib"
        fi
      '';

      copyIbis = ''
        _ibs="$_cache/ibisfs-src"
        if [ ! -d "$_ibs" ]; then
          echo "ibisfs: copying IbisFS library to $_ibs (one-time setup)..." >&2
          mkdir -p "$_ibs"
          cp -r ${ibisfsLib}/. "$_ibs/"
          chmod -R u+w "$_ibs"
          printf 'name: ibisfs\ninclude: .\ndepend: standard-library\n' \
            > "$_ibs/ibisfs.agda-lib"
        fi
      '';

    in
    {
      packages.${system} = {
        lib     = ibisfsLib;
        default = ibisfsLib;
      };

      devShells.${system}.default = piforge.lib.agda.mkShell {
        inherit pkgs;
        version             = "v28";
        useRuntimeLibraries = true;
        extraPackages = with pkgs; [ watchexec ];
        shellHook = copyStdlib + ''
          mkdir -p "$_cache/ibisfs-dev"
          printf '%s\n' "$_stdlib/standard-library.agda-lib" \
            > "$_cache/ibisfs-dev/libraries"
          export AGDA_DIR="$_cache/ibisfs-dev"
        '';
      };

      lib.mkShell = { pkgs, extraPackages ? [], shellHook ? "" }:
        piforge.lib.agda.mkShell {
          inherit pkgs;
          version             = "v28";
          useRuntimeLibraries = true;
          extraPackages = with pkgs; [ watchexec ] ++ extraPackages;
          shellHook = copyStdlib + copyIbis + ''
            mkdir -p "$_cache/ibisfs-lib"
            printf '%s\n%s\n' \
              "$_stdlib/standard-library.agda-lib" \
              "$_ibs/ibisfs.agda-lib" \
              > "$_cache/ibisfs-lib/libraries"
            export AGDA_DIR="$_cache/ibisfs-lib"
          '' + shellHook;
        };
    };
}
