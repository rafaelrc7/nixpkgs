{ stdenv
, lib
, system
, fetchFromGitHub
, graalvm-ce
, gradle
, jdk17
, nativeBuild ? true
}:
stdenv.mkDerivation rec {
  pname = "pkl";
  version = "0.26.2";

  src = fetchFromGitHub {
    owner = "apple";
    repo = "pkl";
    rev = version;
    sha256 = "sha256-Q7B6DRKmgysba+VhvKiTE98UA52i6UUfsvk3Tl/2Rqg=";
    # the build needs the commit id, replace it in postFetch and remove .git manually
    leaveDotGit = true;
    postFetch = ''
      cd "$out"
      export commit_id=$(git rev-parse --short HEAD)
      cp ${./set_commit_id.patch} set_commit_id.patch
      chmod +w set_commit_id.patch
      substituteAllInPlace set_commit_id.patch
      git apply set_commit_id.patch
      rm set_commit_id.patch
      find "$out" -name .git -print0 | xargs -0 rm -rf
    '';
  };

  patches = [ ./use_nix_graalvm_instead_of_download.patch ];

  postPatch = ''
    export graalvmDir="${graalvm-ce}"
    substituteAllInPlace ./buildSrc/src/main/kotlin/BuildInfo.kt
  '';

  nativeBuildInputs = [
    gradle
  ] ++ (if nativeBuild then [ graalvm-ce ] else [ ]);

  mitmCache = gradle.fetchDeps {
    inherit pname;
    data = ./deps.json;
  };

  __darwinAllowLocalNetworking = true;

  gradleBuildTask = if nativeBuild then
                      "assembleNative"
                    else
                      "assemble";

  gradleFlags = [
    "--stacktrace"
    "--info"
    "-x" "spotlessCheck"
    "-DreleaseBuild=true"
    "-Dorg.gradle.java.home=${jdk17}"
  ];

  JAVA_TOOL_OPTIONS = "-Dfile.encoding=utf-8";

  installPhase = if nativeBuild then
      let executableName = {
        "aarch64-darwin" = "pkl-macos-aarch64";
        "x86_64-darwin" = "pkl-macos-amd64";
        "aarch64-linux" = "pkl-linux-aarch64";
        "x86_64-linux" = "pkl-linux-amd64";
      }."${system}";
      in
      ''
        runHook preInstall

        mkdir -p "$out/bin"
        install -Dm755 "./pkl-cli/build/executable/${executableName}" "$out/bin/pkl"

        runHook postInstall
      ''
    else
      ''
        runHook preInstall

        mkdir -p "$out/bin"
        head -n2 ./pkl-cli/build/executable/jpkl | sed 's%java%${jdk17}/bin/java%' > "$out/bin/jpkl"
        tail -n+3 ./pkl-cli/build/executable/jpkl >> "$out/bin/jpkl"
        chmod 755 "$out/bin/jpkl"

        runHook postInstall
      '';

  meta = {
    description = "A configuration as code language with rich validation and tooling.";
    homepage = "https://pkl-lang.org/";
    licence = lib.licenses.asl20;
    platforms = if nativeBuild then
                  [
                    "aarch64-darwin"
                    "x86_64-darwin"
                    "aarch64-linux"
                    "x86_64-linux"
                  ]
                else
                  lib.platforms.all;
    maintainers = with lib.maintainers; [ rafaelrc ];
    mainProgram = if nativeBuild then "pkl" else "jpkl";
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode # mitm cache
    ];
  };
}

