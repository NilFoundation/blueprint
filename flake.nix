{
  description = "Nix flake for zkllvm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    nil_crypto3 = {
      url =
        "git+https://github.com/NilFoundation/crypto3?submodules=1&rev=66096ae733cabc99a763e00e803d710493318563";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nil_crypto3, flake-utils }:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        stdenv = pkgs.llvmPackages_16.stdenv;
      in rec {
        packages = rec {
          crypto3 = nil_crypto3.packages.${pkgs.system}.default;
          zkllvm = stdenv.mkDerivation {
            name = "zkllvm";

            src = self;

            env.CXXFLAGS = toString ([ "-fPIC" ]);

            env.NIX_CFLAGS_COMPILE =
              toString ([ "-Wno-unused-but-set-variable" ]);

            buildInputs = with pkgs; [ cmake pkg-config clang_16
              (boost183.override {
                enableShared = true;
                enableStatic = true;
                enableRelease = true;
                enableDebug = true;
              })
            ];

            # Because crypto3 is header-only, we must propagate it so users
            # of this flake must not specify crypto3 in their derivations manually
            propagatedBuildInputs = [ crypto3 ];

            cmakeFlags =
              [ "-DCMAKE_BUILD_TYPE=Release"
                "-DCMAKE_CXX_STANDARD=17" ];

            doCheck = false;
          };
          default = zkllvm;
        };

        testList = [
            "arithmetics_cpp_example"
            "polynomial_cpp_example"
            "poseidon_cpp_example"
            "merkle_tree_poseidon_cpp_example"
            "uint_remainder_cpp"
            "uint_shift_left"
            "uint_bit_decomposition"
            "uint_bit_composition"
            "compare_eq_cpp"
            "private_input_cpp"
        ];

        checks = {
          default = stdenv.mkDerivation {
            # TODO: rewrite this using overrideAttrs on makePackage
            name = "zkllvm-tests";

            src = self;

            env.CXXFLAGS = toString ([ "-fPIC" ]);

            env.NIX_CFLAGS_COMPILE =
              toString ([ "-Wno-unused-but-set-variable" ]);

            buildInputs = with pkgs; [
              cmake
              ninja
              pkg-config
              clang_16
              boost183
              packages.crypto3
            ];

            cmakeBuildType = "Debug";

            cmakeFlags = [
              "-DCMAKE_CXX_STANDARD=17"
              "-DBUILD_SHARED_LIBS=TRUE"
              "-DCMAKE_ENABLE_TESTS=TRUE"
              "-DCMAKE_C_COMPILER=clang"
              "-DCMAKE_CXX_COMPILER=clang++"
            ];

            ninjaFlags = pkgs.lib.strings.concatStringsSep " " testList;

            doCheck = true;

            checkPhase = ''
              # JUNIT file without explicit file name is generated after the name of the master test suite inside `CMAKE_CURRENT_SOURCE_DIR` (/build/source)
              export BOOST_TEST_LOGGER=JUNIT:HRF
              ctest --verbose -j $NIX_BUILD_CORES --output-on-failure -R "${nixpkgs.lib.concatStringsSep "|" testList}"

              mkdir -p ${placeholder "out"}/test-logs
              find .. -type f -name '*_test.xml' -exec cp {} ${placeholder "out"}/test-logs \;
            '';

            dontInstall = true;
          };
        };

        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              cmake
              pkg-config
              boost183
              clang_16
              clang-tools_16
              packages.crypto3
            ];

            shellHook = ''
              echo "zkllvm dev environment activated"
            '';
          };
        };
      }));
}

# 1 build zkllvm locally with the command 'nix build -L .?submodules=1#'
# 2 redirect to the local build of crypto3: 'nix develop --redirect .#crypto3 /your/path/to/crypto3/result/'
# 3a to build all in zkllvm: 'nix flake -L check .?submodules=1#'
# 3b to build individual targets:
# nix develop . -c cmake -B build -DCMAKE_CXX_STANDARD=17 -DCMAKE_BUILD_TYPE=Debug -DBUILD_SHARED_LIBS=FALSE -DCMAKE_ENABLE_TESTS=TRUE -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
# cd build
# nix develop ../ -c cmake --build . -t arithmetics_cpp_example
