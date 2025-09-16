{
  description = "fe";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";
    systems.url = "github:nix-systems/default";

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs =
    {
      nixpkgs,
      # nixpkgs-stable,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        lib = nixpkgs.lib;
        pkgs = nixpkgs.legacyPackages.${system};
        # stable-pkgs = nixpkgs-stable.legacyPackages.${system};
      in
      # rec
      {
        devShells.default = pkgs.mkShell {
          packages =
            (with pkgs; [
              #- electron
              alsa-lib
              atkmm
              at-spi2-atk
              cairo
              cups
              dbus
              expat
              glib
              glibc
              gtk2
              gtk3
              gtk4
              libdrm
              libxkbcommon
              mesa
              nspr
              nss
              nodePackages.pnpm
              nodejs_20
              pango
              udev

              #- rust
              rustc
              cargo
              cargo-watch
              rustfmt
              clippy
              rust-analyzer
            ])
            ++ (with pkgs.xorg; [
              #- electron
              libXcomposite
              libXdamage
              libXext
              libXfixes
              libXrandr
              libX11
              xcbutil
              libxcb
            ]);

          env = {
            LD_LIBRARY_PATH = lib.makeLibraryPath (
              with pkgs;
              [
                #- electron
                gtk3
                libgbm
              ]
            );
            # ELECTRON_OZONE_PLATFORM_HINT = "auto";
            ELECTRON_OZONE_PLATFORM_HINT = "wayland";
            NIXOS_OZONE_WL = 1;
            GDK_BACKEND = "wayland";

            RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
          };

          shellHook = ''
            # pnpm install

            export PATH="node_modules/.bin:$PATH"
          '';
        };
      }
    );
}
