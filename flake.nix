{
  description = "fw-processing — pnpm monorepo (Turbo) packaged with fetchPnpmDeps + pnpmConfigHook";

  inputs.nixpkgs.url = "nixpkgs/nixos-25.11";

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          inherit (pkgs)
            lib
            stdenv
            fetchPnpmDeps
            pnpmConfigHook
            pnpm_10
            nodejs_20
            turbo
            jq
            ;

          pname = "fw-processing";
          version = (lib.importJSON ./package.json).version;
          src = lib.cleanSource ./.;

          meta = {
            description = "Form processing / React–Redux–Yjs workspace";
            license = lib.licenses.mit;
            maintainers = with lib.maintainers; [ j03 ];
            platforms = lib.platforms.linux;
          };

          scope = "react-redux-yjs";

          #
          # Pruned subset (Turbo) — same role as the old *-turbo package.
          #
          fw-processing-react-redux-yjs-turbo = stdenv.mkDerivation {
            name = "${pname}-${scope}-turbo-${version}";
            inherit src version;
            pname = "${pname}-${scope}-turbo";

            nativeBuildInputs = [ turbo ];

            dontConfigure = true;

            buildPhase = ''
              runHook preBuild
              turbo prune --scope "${scope}"
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mv out $out
              runHook postInstall
            '';

            meta = meta // {
              description = "Turbo-pruned workspace subset (pnpm workspace, lockfile inside)";
            };
          };

          #
          # Fixed-output pnpm dependency store (replaces the old ad-hoc nodeModules FOD).
          #
          pnpmDeps =
            fetchPnpmDeps {
              inherit pname version src;
              pnpm = pnpm_10;
              fetcherVersion = 3;
              hash = "sha256-KzsmNg2hNKx5ePNrM9SBi0gkA2m+s4IQnJvXNx6rlDg=";
            };

          #
          # Full install + Turbo build for the scoped package (replaces yarn + manual symlinks).
          #
          fw-processing = stdenv.mkDerivation {
            name = "${pname}-${version}";
            inherit pname version src pnpmDeps;

            nativeBuildInputs = [
              nodejs_20
              pnpmConfigHook
              pnpm_10
              jq
            ];

            # Avoid pnpm trying to download the exact `packageManager` pin (no network in sandbox).
            patchPhase = ''
              runHook prePatch
              jq 'del(.packageManager)' package.json > package.json.tmp
              mv package.json.tmp package.json
              runHook postPatch
            '';

            # pnpm expects a writable HOME for its metadata cache.
            preBuild = ''
              export HOME="$TMPDIR"
            '';

            buildPhase = ''
              runHook preBuild
              pnpm --filter "${scope}" run build
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib/${pname}"
              cp -r packages/${scope}/dist "$out/lib/${pname}/"
              cp packages/${scope}/package.json "$out/lib/${pname}/"
              runHook postInstall
            '';

            passthru = {
              inherit pnpmDeps fw-processing-react-redux-yjs-turbo;
            };

            meta = meta // {
              description = "Built ${scope} package (dist + package.json)";
            };
          };
        in
        {
          inherit fw-processing fw-processing-react-redux-yjs-turbo;

          # Back-compat names from the old flake (Yarn path removed).
          fw-processing-react-redux-yjs-nodeModules = pnpmDeps;
          fw-processing-react-redux-yjs-nodePackage = fw-processing;

          default = fw-processing;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              nodejs_20
              pnpm_10
              turbo
            ];
            shellHook = ''
              echo "fw-processing dev: use «pnpm install» then «pnpm run build» / «pnpm run dev»."
            '';
          };
        }
      );
    };
}
