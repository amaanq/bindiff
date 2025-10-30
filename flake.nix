{
  description = "BinDiff - A binary comparison tool";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          binexportSrc = pkgs.fetchFromGitHub {
            owner = "google";
            repo = "binexport";
            rev = "17c4363b7d2ece44161a0ebced60f4e66d309af8";
            hash = "sha256-DTelb3TaR74QLM/EZleu6snRFqwpoieH6+Uufm2Y83g=";
          };

          sqliteAmalgamation = pkgs.fetchzip {
            url = "https://sqlite.org/2024/sqlite-amalgamation-3450100.zip";
            hash = "sha256-w31VCEdATe4s6craHLrRU17o9ln8XJSK122eUxY/3pA=";
            stripRoot = false;
          };

          abslSrc = pkgs.fetchzip {
            url = "https://github.com/abseil/abseil-cpp/archive/01a4ea7fbbe26f7ca8ce3bcebdc7b0446d953a5d.zip";
            hash = "sha256-Yzc952mevnGgsmeW/drnGjWVFBb8j4xa16bnQ5s16E0=";
            stripRoot = false;
          };

          protobufSrc = pkgs.fetchzip {
            url = "https://github.com/protocolbuffers/protobuf/archive/refs/tags/v31.0.tar.gz";
            hash = "sha256-ZBxyVlKufPn5Fi31j/YdnVXHRvL8myz2vP4Xi1pjbVE=";
            stripRoot = false;
          };

          idaSdk = pkgs.fetchFromGitHub {
            owner = "HexRaysSA";
            repo = "ida-sdk";
            rev = "7acfc0f417a116775012f0f154deb43b62d5a43d";
            hash = "sha256-JBcfBOE3qsdB1cg1uHH/a8E7ejMPZo/xhZ8jkKiXnPY=";
          };

          mkBinDiff =
            {
              enableIda ? false,
              enableBinaryNinja ? false,
            }:
            pkgs.stdenv.mkDerivation {
              pname = "bindiff";
              version = "8.0.0";

              src = ./.;

              nativeBuildInputs = [
                pkgs.cmake
                pkgs.ninja
                pkgs.autoPatchelfHook
                pkgs.makeWrapper
                pkgs.git
              ];

              buildInputs = [
                pkgs.stdenv.cc.cc.lib
                pkgs.boost183
                pkgs.zlib
                pkgs.openssl
              ];

              autoPatchelfIgnoreMissingDeps =
                [ ]
                ++ pkgs.lib.optional enableIda "libida.so"
                ++ pkgs.lib.optional enableBinaryNinja "libbinaryninjacore.so";

              preConfigure = ''
                export BINDIFF_BINEXPORT_DIR="${binexportSrc}"

                mkdir -p build/_deps

                mkdir -p build/_deps/sqlite-src
                cp -r ${sqliteAmalgamation}/sqlite-amalgamation-3450100/* build/_deps/sqlite-src/

                mkdir -p build/_deps/absl-src
                cp -r ${abslSrc}/abseil-cpp-01a4ea7fbbe26f7ca8ce3bcebdc7b0446d953a5d/* build/_deps/absl-src/

                mkdir -p build/_deps/protobuf-src
                cp -r ${protobufSrc}/protobuf-31.0/* build/_deps/protobuf-src/

                mkdir -p build/_deps/idasdk-src
                cp -r ${idaSdk}/* build/_deps/idasdk-src/
              '';

              configurePhase = ''
                runHook preConfigure

                cmake -B build -G Ninja \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBINDIFF_BINEXPORT_DIR=${binexportSrc} \
                  -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
                  -DFETCHCONTENT_SOURCE_DIR_SQLITE="$PWD/build/_deps/sqlite-src" \
                  -DFETCHCONTENT_SOURCE_DIR_ABSL="$PWD/build/_deps/absl-src" \
                  -DFETCHCONTENT_SOURCE_DIR_PROTOBUF="$PWD/build/_deps/protobuf-src" \
                  -DFETCHCONTENT_SOURCE_DIR_IDASDK="$PWD/build/_deps/idasdk-src" \
                  -DIdaSdk_ROOT_DIR="$PWD/build/_deps/idasdk-src/src" \
                  -DBINEXPORT_ENABLE_IDAPRO=ON \
                  -DBUILD_TESTING=OFF \
                  -DBINDIFF_BUILD_TESTING=OFF \
                  -Wno-dev \
                  ${pkgs.lib.optionalString enableBinaryNinja "-DBINEXPORT_ENABLE_BINARYNINJA=ON"} \
                  ${pkgs.lib.optionalString (!enableBinaryNinja) "-DBINEXPORT_ENABLE_BINARYNINJA=OFF"}

                runHook postConfigure
              '';

              buildPhase = ''
                runHook preBuild
                ninja -C build

                ${pkgs.lib.optionalString enableIda ''
                  ninja -C build _deps/binexport-build/ida/binexport12_ida64.so
                ''}

                runHook postBuild
              '';

              installPhase = ''
                runHook preInstall

                mkdir -p $out/bin

                if [ -f "build/bindiff" ]; then
                  cp build/bindiff $out/bin/

                  wrapProgram $out/bin/bindiff \
                    --prefix PATH : "/run/current-system/sw/bin"
                fi

                if [ -d "build/bindiff-prefix/bin" ]; then
                  cp build/bindiff-prefix/bin/* $out/bin/ 2>/dev/null || true
                fi

                ${pkgs.lib.optionalString enableIda ''
                  mkdir -p $out/share/bindiff/plugins/idapro

                  cp build/ida/bindiff8_ida64.so $out/share/bindiff/plugins/idapro/

                  cp build/_deps/binexport-build/ida/binexport12_ida64.so $out/share/bindiff/plugins/idapro/
                ''}

                ${pkgs.lib.optionalString enableBinaryNinja ''
                  mkdir -p $out/share/bindiff/plugins/binaryninja
                  find build -name "*binaryninja*.so" | while read plugin; do
                    cp "$plugin" $out/share/bindiff/plugins/binaryninja/ 2>/dev/null || true
                  done
                ''}

                runHook postInstall
              '';

              meta = {
                description =
                  "BinDiff - A binary comparison tool"
                  + pkgs.lib.optionalString enableIda " with IDA Pro support"
                  + pkgs.lib.optionalString enableBinaryNinja " with Binary Ninja support";
                homepage = "https://github.com/google/bindiff";
                license = pkgs.lib.licenses.asl20;
                platforms = pkgs.lib.platforms.linux;
                maintainers = [ ];
              };
            };
        in
        {

          default = mkBinDiff { };

          bindiff-ida = mkBinDiff { enableIda = true; };

          bindiff-binja = mkBinDiff { enableBinaryNinja = true; };

          bindiff-full = mkBinDiff {
            enableIda = true;
            enableBinaryNinja = true;
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [ self.packages.${system}.default ];
            packages = [
              pkgs.cmake
              pkgs.ninja
              pkgs.clang-tools
            ];
          };
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/bindiff";
        };
      });

      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          options.programs.bindiff = {
            enable = lib.mkEnableOption "BinDiff - Quickly find differences and similarities in disassembled code";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.default;
              defaultText = lib.literalExpression "bindiff";
              description = "BinDiff package to use";
            };

            enableIdaPlugin = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Install IDA Pro plugin";
            };

            enableBinaryNinjaPlugin = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Install Binary Ninja plugin";
            };
          };

          config = lib.mkIf config.programs.bindiff.enable (
            lib.mkMerge [
              {
                environment.systemPackages = [
                  (
                    if config.programs.bindiff.enableIdaPlugin && config.programs.bindiff.enableBinaryNinjaPlugin then
                      self.packages.${pkgs.system}.bindiff-full
                    else if config.programs.bindiff.enableIdaPlugin then
                      self.packages.${pkgs.system}.bindiff-ida
                    else if config.programs.bindiff.enableBinaryNinjaPlugin then
                      self.packages.${pkgs.system}.bindiff-binja
                    else
                      config.programs.bindiff.package
                  )
                ];
              }

              (lib.mkIf config.programs.bindiff.enableIdaPlugin {
                environment.pathsToLink = [ "/share/bindiff/plugins/idapro" ];
              })

              (lib.mkIf config.programs.bindiff.enableBinaryNinjaPlugin {
                environment.pathsToLink = [ "/share/bindiff/plugins/binaryninja" ];
              })
            ]
          );
        };
    };
}
