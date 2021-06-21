{ sources ? import ./nix/sources.nix { }
, haskellNix ? import sources.haskell-nix { }
, pkgs ? import sources.nixpkgs haskellNix.nixpkgsArgs
, ghc ? "ghc8105"
, toolsGhc ? "ghc8105"
, node ? "nodejs_latest"
, hsPkgs ? import ./default.nix { inherit pkgs ghc node; }
}:
let
  ghc_ver = pkgs.haskell-nix.compiler."${ghc}".version;
  ghc_pre_9 = !(pkgs.lib.versionAtLeast ghc_ver "9");
in
hsPkgs.shellFor {
  packages = ps:
    with ps; [
      inline-js
      inline-js-core
      inline-js-examples
      inline-js-tests
    ];

  withHoogle = true;

  tools =
    let
      args = {
        version = "latest";
        compiler-nix-name = toolsGhc;
        modules = [{ dontPatchELF = false; } { dontStrip = false; }];
      };
    in
    {
      brittany = args;
      cabal-fmt = args;
      floskell = args;
      ghcid = args;
      hlint = args;
      hoogle = args;
      ormolu = args;
      stylish-haskell = args;
    };

  nativeBuildInputs = [
    (pkgs.haskell-nix.cabalProject {
      src = pkgs.applyPatches {
        src = pkgs.fetchFromGitHub {
          owner = "phadej";
          repo = "cabal-extras";
          rev = "43fe572c3b6fe378be965a37a4a0e1c576296eed";
          sha256 = "sha256-HlfeS+OocwnEDLhue4qnHDhW0ZVRf4PVvc4V1546nAs=";
        };
        patches = [ ./nix/cabal-extras.patch ];
      };
      compiler-nix-name = toolsGhc;
      configureArgs = "--disable-benchmarks --disable-tests";
      modules = [
        { dontPatchELF = false; }
        { dontStrip = false; }
        { reinstallableLibGhc = true; }
      ];
    }).cabal-docspec.components.exes.cabal-docspec
  ] ++ pkgs.lib.optionals ghc_pre_9 [
    (pkgs.haskell-nix.cabalProject {
      src = pkgs.fetchFromGitHub {
        owner = "haskell";
        repo = "haskell-language-server";
        rev = "ghcide-v1.4.0.2";
        sha256 = "sha256-mzIPZS0Ov+xUhb9i1GeACJm7gUZC9D/avle4pJreLdo=";
        fetchSubmodules = true;
      };
      compiler-nix-name = ghc;
      configureArgs =
        "--disable-benchmarks --disable-tests -fall-formatters -fall-plugins";
      modules = [{ dontPatchELF = false; } { dontStrip = false; }];
    }).haskell-language-server.components.exes.haskell-language-server
  ] ++ [
    pkgs.haskell-nix.internal-cabal-install
    pkgs.niv
    pkgs.nixfmt
    pkgs.nixpkgs-fmt
    pkgs."${node}"
  ];

  exactDeps = true;
}
