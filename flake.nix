{
  description = "fe";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";
    systems.url = "github:nix-systems/default";

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-stable,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        stable-pkgs = nixpkgs-stable.legacyPackages.${system};
      in
      rec {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            zig
            zls
            lldb
            gdb
            pkg-config
            valgrind
            wabt
            tracy
            renderdoc

            # libs
            sdl3
            sdl3-ttf
            xorg.libX11.dev

            fontconfig

            wasmtime-c-api

            # glfw
            glfw-wayland
            wayland
            libxkbcommon
            xorg.libXcursor.dev
            xorg.libXrandr.dev
            xorg.libXinerama.dev
            xorg.libXi.dev

            # wayland
            wayland
            wayland-protocols
            wayland-scanner

            glib
          ];

          env = {
            # "SDL_VIDEODRIVER" = "wayland";
          };

          shellHook = '''';
        };

        wasmtime-c-api = pkgs.stdenv.mkDerivation rec {
          name = "wasmtime-c-api";
          version = "30.0.2";

          src = pkgs.fetchurl {
            url = "https://github.com/bytecodealliance/wasmtime/releases/download/v${version}/wasmtime-v${version}-${system}-c-api.tar.xz";
            sha256 =
              if system == "x86_64-linux" then "0mad44024z5b76dnz46x64p6vqdmmrvdfyc62swby523sr454xvc" else "TODO";
          };

          unpackPhase = ''
            tar -xf $src
          '';

          installPhase = ''
            mkdir -p $out/include
            cp -r ./*/include/* $out/include/

            mkdir -p $out/lib
            cp ./*/lib/* $out/lib/
          '';

          meta = {
            description = "Wasmtime C API library";
            homepage = "https://wasmtime.dev/";
            license = pkgs.lib.licenses.asl20;
          };
        };
      }
    );
}
