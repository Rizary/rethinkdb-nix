{ lib, sourcePrep, fetchList, fetchDependencies, fetchInfos, alwaysFetch, rethinkdbBuildInputsCC, rethinkdbBuildInputs, rawSource }:
with lib;

rec {
  buildDeps = buildDepsWith reCC builtins.currentSystem;
  buildDepsWith = cc: system: let
    rethinkdb = unsafeDiscardStringContext (toString rawSource); # TODO remove dependency on specific version
  in mkSimpleDerivation (rec {
    name = "rethinkdb-deps-${cc.name}-${system}";
    inherit system;
    buildInputs = rethinkdbBuildInputsCC cc ++ [ cc pkgs.nodejs ];
    buildCommand = ''
      cp -r ${rethinkdb}/* .
      chmod -R u+w .
      # sed -i "s/GYPFLAGS=/GYPFLAGS='-Dstandalone_static_library=1 '/" mk/support/pkg/v8.sh
      for x in $deps; do
        cp -r ''${!x}/* .
        chmod -R u+w .
      done
      patchShebangs . > /dev/null
      ./configure ${alwaysFetch}
      ${make} fetch
      patchShebangs external > /dev/null
      ${make} support VERBOSE=1

      bash $fattenArchives build/external/v8_*/lib/*.a
      
      mkdir -p $out/build/
      cp -r build/external $out/build/
    '';
    env = {
      deps = map (info: info.varName) fetchInfos;
      fattenArchives = ./fattenArchives.sh;

      # TODO: should eventually not need this
      __noChroot = true; 
    } // listToAttrs (for fetchInfos (depInfo:
      { name = depInfo.varName; value = getAttr depInfo.varName fetchDependencies; }));
  });

  debugBuild = debugBuildWith reCC builtins.currentSystem;
  debugBuildWith = cc: system: mkSimpleDerivation rec {
    name = "rethinkdb-${env.src.version}-build-debug-${cc.name}-${system}";
    inherit system;
    env = {
      src = sourcePrep;
      deps = buildDepsWith cc system;
    };
    buildInputs = rethinkdbBuildInputsCC cc ++ [ cc ];
    buildCommand = ''
      cp -r $src/* .
      chmod -R u+w .
      patchShebangs . > /dev/null
      ./configure --fetch jemalloc
      cp -r $deps/* .
      chmod -R u+w .
      ${make} DEBUG=1
      mkdir -p $out/build/debug
      cp build/debug/rethinkdb{,-unittest} $out/build/debug
    '';
  };

  matrixBuilds = listToAttrs (concatLists (
    (flip mapAttrsToList) { inherit (pkgs)
        gcc48 gcc49 gcc5 gcc6 gcc7
        clang_34 clang_35 clang_37 clang_38 clang_39 clang_4 clang_5;
    } (ccName: cc: for [ "x86_64" "i686" ] (arch:
        { name = "${ccName}-${arch}";
          value = debugBuildWith cc "${arch}-linux"; }))));
}
