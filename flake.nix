{
  description = "fe";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    # nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";
    systems.url = "github:nix-systems/default";

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
    };
  };

  outputs =
    {
      nixpkgs,
      # nixpkgs-stable,
      flake-utils,
      rust-overlay,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        # pkgs = nixpkgs.legacyPackages.${system};
        # # stable-pkgs = nixpkgs-stable.legacyPackages.${system};
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };

        toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

        packages = with pkgs; [
          cargo
          cargo-tauri
          toolchain
          rust-analyzer-unwrapped
          # bun
          just
          entr
        ];

        nativeBuildLibraries = with pkgs; [
          webkitgtk_4_1
          gtk3
          dbus
          openssl
          glib
          librsvg
        ];

        nativeBuildPackages =
          with pkgs;
          [
            pkg-config
            libsoup_2_4
          ]
          ++ nativeBuildLibraries;

        libraries =
          with pkgs;
          [
            cairo
            gdk-pixbuf
          ]
          ++ nativeBuildLibraries;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = packages;

          nativeBuildInputs = nativeBuildPackages;

          shellHook = with pkgs; ''
            export PROJECT_ROOT=$PWD

            export PATH="$PATH:./bun/"

            export LD_LIBRARY_PATH="${lib.makeLibraryPath libraries}:$LD_LIBRARY_PATH"

            export OPENSSL_INCLUDE_DIR="${openssl.dev}/include/openssl"

            export OPENSSL_LIB_DIR="${openssl.out}/lib"

            export OPENSSL_ROOT_DIR="${openssl.out}"

            export RUST_SRC_PATH="${toolchain}/lib/rustlib/src/rust/library"
          '';
        };
      }
    );
}
