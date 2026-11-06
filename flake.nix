{
  description = "RustiCal CalDAV/CardDAV server (RafaelMuijsert fork)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      perSystem = flake-utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          rustical = pkgs.callPackage ./nix/package.nix { };
        in
        {
          packages = {
            default = rustical;
            rustical = rustical;
          };

          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              # The task runner, similar to make
              just
              # For frontend modules
              deno
              # For documentation
              mkdocs
              python314Packages.mkdocs-material

              cargo-vet
              cargo-about
              cargo-deny
            ];
          };
        }
      );
    in
    perSystem
    // {
      nixosModules = {
        default = import ./nix/module.nix { inherit self; };
        rustical = import ./nix/module.nix { inherit self; };
      };

      overlays.default = final: _prev: {
        rustical = self.packages.${final.stdenv.hostPlatform.system}.default;
      };
    };
}
