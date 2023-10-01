# TeX Live {#sec-language-texlive}

Since release 15.09 there is a new TeX Live packaging that lives entirely under attribute `texlive`, with a few prebuilt environments exported at the top level, such as `texliveSmall`, `texliveFull`.

Since release 23.11, `texlive` uses `withPackages` to create environments, in line with other languages. The legacy `texlive.combine` function is deprecated and will be removed in future releases. Custom TeX packages should be built as multi-output derivations and support for the legacy `passthru.pkgs` attribute is also deprecated and will be removed. See the examples below on how to switch from `texlive.combine` to `withPackages`.

## User's guide {#sec-language-texlive-user-guide}

- For basic usage just pull `texliveBasic` for an environment with basic LaTeX support.

- Packages cannot be installed individually, but must be combined in an environment. There are several prebuilt environments available, one per scheme provided by TeX Live. To add a package to an existing environment, use `withPackages`. Most CTAN packages should be available.

  ```nix
  texliveSmall.withPackages (ps: with ps; [ collection-langkorean algorithms cm-super ])
  ```

- The packages are listed in `texlive.pkgs` and can be inspected e.g. by `nix repl`.

  ```ShellSession
  $ nix repl
  nix-repl> :l <nixpkgs>
  nix-repl> texlive.pkgs.collection-[TAB]
  ```

- By default you only get executables and files needed during runtime, plus man pages in the `"man"` output (installed by default if using `nix-env`) and info pages in the `"info"` output. To add the documentation of a single package, you may specify its `"texdoc"` output:

  ```nix
  texliveSmall.withPackages (ps: with ps; [ texdoc ulem ulem.texdoc ])
  ```
  The `texdoc` package adds a convenient script to search for documentation:
  ```ShellSession
  $ texdoc ulem
  ```

  To add documentation for all the packages in the environment, use `.overrideTeXConfig` as follows:

  ```nix
  texliveSmall.overrideTeXConfig (prev: {
    requiredTeXPackages = ps: prev.requiredTeXPackages ps ++ [ ps.texdoc ];
    withDocs = true;
    # withSources = true;
  })
  ```

  The function `.overrideTeXConfig` accepts attribute sets as argument as well:

  ```nix
  texliveSmall.overrideTeXConfig { withDocs = true; }
  ```

  All of the above functions can be applied multiple times.

- TeX Live packages are also available under `texlive.pkgs` as derivations with outputs `out`, `tex`, `texdoc`, `texsource`, `tlpkg`, `man`, `info`. They cannot be installed outside of `texlive.combine` but are available for other uses. To repackage a font, for instance, use

  ```nix
  stdenvNoCC.mkDerivation rec {
    src = texlive.pkgs.iwona;

    inherit (src) pname version;

    installPhase = ''
      runHook preInstall
      install -Dm644 fonts/opentype/nowacki/iwona/*.otf -t $out/share/fonts/opentype
      runHook postInstall
    '';
  }
  ```

  See `biber`, `iwona` for complete examples.

### Switching from `texlive.combine` to `withPackages` {#sec-language-texlive-switching-from-combine}

Below are some examples of `texlive.combine` calls followed by the equivalent calls to `withPackages` and `overrideTeXConfig`. Packages built outside of `texlive` and containing binaries may require specifying the `tex` output, depending on the desired outcome.

- Install `scheme-medium`, `epsf`, `collection-latexextra`, all containers of `cm-super`, and `myTeXPackage` (a custom package built outside of `texlive`, containing some binaries and some TeX files):
  ```nix
  # deprecated texlive.combine
  texlive.combine {
    inherit (texlive) scheme-medium epsf collection-latexextra;
    inherit myTeXPackage; # does not include binaries
    extraName = "my-env";
    pkgFilter = pkgFilter = pkg:
      pkg.tlType == "run" || pkg.tlType == "bin" || pkg.hasManpages || pkg.pname == "cm-super";
  }

  # new withPackages, without myTeXPackage binaries
  texliveMedium.withPackages (ps: with ps; [ epsf collection-latexextra
    cm-super.texdoc cm-super.texsource # add other containers of cm-super
    myTeXPackage.tex # add only the tex files of myTeXPackage
  ])
  # new withPackages, with LaTeXML binaries
  texliveMedium.withPackages (ps: with ps; [ epsf collection-latexextra
    cm-super.texdoc cm-super.texsource # add other containers of cm-super
    myTeXPackage # add outputs "out", "tex", "tlpkg" (if present) of myTeXPackage
  ])
  ```
  Note that `extraName`, `extraVersion` are not supported.

- Install `scheme-small` with documentation for all packages:
  ```nix
  # deprecated texlive.combine
  texlive.combine {
    inherit (texlive) scheme-small;
    pkgFilter = pkg:
      pkg.tlType == "run" || pkg.tlType == "bin" || pkg.tlType == "doc";
  }

  # new withPackages
  texliveSmall.overrideTeXConfig { withDocs = true; }
  ```

## Custom packages {#sec-language-texlive-custom-packages}

You may find that you need to use an external TeX package. A derivation for such package has to provide the contents of the "texmf" directory in its `"tex"` output. The content should be laid out according to the TeX Directory Structure.

Dependencies can be specified via the attribute `passthru.requiredTeXPackages`, which must be a function taking a package set and returning a list of packages.

Here is a (very verbose) example. See `sagetex` for how to create a derivation with no `"out"` output. See also the packages `auctex`, `eukleides`, `mftrace` for more examples.

```nix
with import <nixpkgs> {};

let
  foiltex = stdenvNoCC.mkDerivation {
    pname = "latex-foiltex";
    version = "2.1.4b";

    outputs = [ "out" "tex" ];
    passthru.requiredTeXPackages = ps: with ps; [ latex ];

    srcs = [
      (fetchurl {
        url = "http://mirrors.ctan.org/macros/latex/contrib/foiltex/foiltex.dtx";
        hash = "sha256-/2I2xHXpZi0S988uFsGuPV6hhMw8e0U5m/P8myf42R0=";
      })
      (fetchurl {
        url = "http://mirrors.ctan.org/macros/latex/contrib/foiltex/foiltex.ins";
        hash = "sha256-KTm3pkd+Cpu0nSE2WfsNEa56PeXBaNfx/sOO2Vv0kyc=";
      })
    ];

    unpackPhase = ''
      runHook preUnpack

      for _src in $srcs; do
        cp "$_src" $(stripHash "$_src")
      done

      runHook postUnpack
    '';

    nativeBuildInputs = [ texliveBasic ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      # Generate the style files
      latex foiltex.ins

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"

      path="$tex/tex/latex/foiltex"
      mkdir -p "$path"
      cp *.{cls,def,clo} "$path/"

      runHook postInstall
    '';

    meta = with lib; {
      description = "A LaTeX2e class for overhead transparencies";
      license = licenses.unfreeRedistributable;
      maintainers = with maintainers; [ veprbl ];
      platforms = platforms.all;
    };
  };

  latex_with_foiltex = texliveBasic.withPackages (_: [ foiltex ]);
in
  runCommand "test.pdf" {
    nativeBuildInputs = [ latex_with_foiltex ];
  } ''
cat >test.tex <<EOF
\documentclass{foils}

\title{Presentation title}
\date{}

\begin{document}
\maketitle
\end{document}
EOF
  pdflatex test.tex
  cp test.pdf $out
''
```

### Switching from `passthru.pkgs` to multi-output {#sec-language-texlive-switching-from-passthru-pkgs}
Packages that were defined using the `passthru.pkgs` attribute must be rebuilt as multi-output derivations. In most cases, this simply means dropping `passthru.pkgs` and `passthru.tlType`:
```nix
  # deprecated passthru.pkgs
  LaTeXML = buildPerlPackage rec {
    # pname, version, ...
    outputs = [ "out" "tex" ];
    passthru = {
      tlType = "run";
      pkgs = [ LaTeXML.tex ];
    }
  };

  # new multi-output
  LaTeXML = buildPerlPackage rec {
    # pname, version, ...
    outputs = [ "out" "tex" ];
  };
```
For more complicated packages, the subpackages with `tlType` values `"bin"`, `"run"`, `"doc"`, `"source"`, `"tlpkg"` must be provided as outputs with names respectively `"out"`, `"tex"`, `"texdoc"`, `"texsource"`, `"tlpkg"`.

The attribute `passthru.tlDeps` must be converted to the function `passthru.requiredTeXPackages`:
```nix
# deprecated passthru.tlDeps
passthru.tlDeps = with texlive; [ collection-pstricks ];
# new passthru.requiredTeXPackages
passthru.requiredTeXPackages = ps: with ps; [ collection-pstricks ];
```
