{
  description = "headfit.elf, built offline from this repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    guest-runtime = {
      url = "github:V-Sekai-fire/contract-guest-runtime";
      flake = false;
    };
    guest-common = {
      url = "github:V-Sekai-fire/contract-guest-common";
      flake = false;
    };
    lbfgsb = {
      url = "github:V-Sekai-fire/contract-lbfgsb";
      flake = false;
    };
    sinew-align = {
      url = "github:V-Sekai-fire/contract-sinew-align";
      flake = false;
    };
    drape = {
      url = "github:V-Sekai-fire/interactor-drape";
      flake = false;
    };
    riscv64-sysroot = {
      url = "github:V-Sekai-fire/repository-riscv64-sysroot";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      # Where guest/CMakeLists.txt looks for each sibling under WEFT_ROOT.
      siblings = {
        "2-contract/guest-runtime" = inputs.guest-runtime;
        "2-contract/guest-common" = inputs.guest-common;
        "2-contract/lbfgsb" = inputs.lbfgsb;
        "2-contract/sinew-align" = inputs.sinew-align;
        "3-interactor/drape" = inputs.drape;
        "5-repository/riscv64-sysroot" = inputs.riscv64-sysroot;
      };

      headfit = { lib, stdenvNoCC, cmake, ninja, python3, llvmPackages }:
        let
          place = path: src: ''
            mkdir -p weft/${dirOf path}
            ln -s ${src} weft/${path}
          '';
          pin = path: src: "${path} ${src.rev}";
        in
        stdenvNoCC.mkDerivation {
          pname = "headfit-elf";
          version = self.shortRev or "dirty";
          src = lib.cleanSourceWith {
            src = self;
            filter = path: _:
              !(builtins.elem (baseNameOf path) [
                "flake.nix"
                "flake.lock"
                ".github"
              ]);
          };
          nativeBuildInputs = [
            cmake
            ninja
            python3
            llvmPackages.clang-unwrapped
            llvmPackages.lld
            llvmPackages.bintools-unwrapped
          ];
          dontUseCmakeConfigure = true;
          # The guest ELF ships as the linker wrote it.
          dontFixup = true;
          buildPhase = ''
            ${lib.concatStrings (lib.mapAttrsToList place siblings)}
            cmake -S guest -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
              -DCMAKE_TOOLCHAIN_FILE=$PWD/weft/5-repository/riscv64-sysroot/toolchain.cmake \
              -DWEFT_ROOT=$PWD/weft
            cmake --build build --target headfit
          '';
          doCheck = true;
          checkPhase = ''
            python3 tests/headfit/check_elf.py build/headfit
            python3 - build/headfit single.elf <<'PY'
            import sys
            b = bytearray(open(sys.argv[1], "rb").read())
            i = b.find(b"SBXV(\0\0\0")
            b[i + 4] = 24
            open(sys.argv[2], "wb").write(b)
            PY
            if python3 tests/headfit/check_elf.py single.elf; then
              echo "the check passed a 24-byte Variant"
              exit 1
            fi
          '';
          installPhase = ''
            mkdir -p $out
            cp build/headfit $out/headfit.elf
            cat > $out/headfit.elf.siblings.txt <<'TXT'
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList pin siblings)}
            TXT
          '';
        };

      overlay = final: _: {
        headfit-elf = final.callPackage headfit {
          llvmPackages = final.llvmPackages_21;
        };
      };
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ overlay ];
      };
    in
    {
      overlays.default = overlay;
      packages.${system} = {
        headfit-elf = pkgs.headfit-elf;
        default = pkgs.headfit-elf;
      };
    };
}
