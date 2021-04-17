params: with params;
# combine =
args@{
  pkgFilter ? (pkg: pkg.tlType == "run" || pkg.tlType == "bin" || pkg.pname == "core")
, extraName ? "combined"
, extraVersion ? ""
, ...
}:
let
  pkgSet = removeAttrs args [ "pkgFilter" "extraName" "extraVersion" ] // {
    # include a fake "core" package
    core.pkgs = [
      (bin.core.out // { pname = "core"; tlType = "bin"; })
      (bin.core.doc // { pname = "core"; tlType = "doc"; })
    ];
  };
  pkgList = rec {
    all = lib.filter pkgFilter (combinePkgs pkgSet);
    splitBin = builtins.partition (p: p.tlType == "bin") all;
    bin = mkUniqueOutPaths splitBin.right
      ++ lib.optional
          (lib.any (p: p.tlType == "run" && p.pname == "pdfcrop") splitBin.wrong)
          (lib.getBin ghostscript);
    nonbin = mkUniqueOutPaths splitBin.wrong;

    # extra interpreters needed for shebangs, based on 2015 schemes "medium" and "tetex"
    # (omitted tk needed in pname == "epspdf", bin/epspdftk)
    pkgNeedsPython = pkg: pkg.tlType == "run" && lib.elem pkg.pname
      [ "de-macro" "pythontex" "dviasm" "texliveonfly" ];
    pkgNeedsRuby = pkg: pkg.tlType == "run" && pkg.pname == "match-parens";
    extraInputs =
      lib.optional (lib.any pkgNeedsPython splitBin.wrong) python3
      ++ lib.optional (lib.any pkgNeedsRuby splitBin.wrong) ruby;

    # names of hyphenation packages (only part after -)
    hyphen = lib.concatMap
      (p: let m = (builtins.match "(hyphen|dehyph)-(.*)" p.pname); in
        if builtins.isNull m then [ ] else builtins.tail m)
      splitBin.wrong;
  };

  uniqueStrings = list: lib.sort (a: b: a < b) (lib.unique list);

  mkUniqueOutPaths = pkgs: uniqueStrings
    (map (p: p.outPath) (builtins.filter lib.isDerivation pkgs));

  name = "texlive-${extraName}-${bin.texliveYear}${extraVersion}";

  texmf = (buildEnv {
    name = "${name}-tex";
    extraPrefix = "/share/texmf";
    ignoreCollisions = false;
    paths = pkgList.nonbin;
    postBuild =
    # link info and man pages
    ''
      for d in {info,man}; do
        [[ -e "$out/share/texmf/doc/$d" ]] && ln -s "texmf/doc/$d" "$out/share/$d"
      done
    '';
  }).overrideAttrs (_: { allowSubstitutes = true; });

in (buildEnv {
  inherit name;

  ignoreCollisions = false;
  paths = pkgList.bin ++ [ texmf ];
  pathsToLink = [
    "/"
    "/share/texmf" # ensure these are writeable directories and not symlinks
    "/share/texmf/scripts"
    "/share/texmf/web2c"
    "/share/texmf/tex/generic/config"
  ];

  buildInputs = [ makeWrapper ] ++ pkgList.extraInputs;

  postBuild = ''
    cd "$out"
    export PATH="$out/bin:$out/share/texmf/scripts/texlive:${perl}/bin:$PATH"
    export TEXMFCNF="$out/share/texmf/web2c"
    export TEXMFDIST="$out/share/texmf"
    export TEXMFSYSCONFIG="$out/share/texmf-config"
    export TEXMFSYSVAR="$out/share/texmf-var"
    export PERL5LIB="$out/share/texmf/scripts/texlive:${bin.core.out}/share/texmf-dist/scripts/texlive"
  '' +
    # patch texmf-dist  -> $out/share/texmf
    # patch texmf-local -> $out/share/texmf
    # TODO: perhaps do lua actions?
    # tried inspiration from install-tl, sub do_texmf_cnf
  ''
    {
      local cnfLua="$out/share/texmf/web2c/texmfcnf.lua"
      if [[ -e "$cnfLua" ]]; then
        local cnfLuaOrig="$(realpath "$cnfLua")"
        rm "$cnfLua"
        substitute $cnfLuaOrig $cnfLua \
          --replace 'texmf-dist"' 'texmf"' \
          --replace '= texmflocal' '= "'"$out/share/texmf"'"' \
          --replace '$SELFAUTOLOC' "$out" \
          --replace 'selfautodir:' "$out/share/" \
          --replace 'selfautoparent:' "$out/share/"
      fi

      local cnf="$out/share/texmf/web2c/texmf.cnf"
      local cnfOrig="$(realpath "$cnf")"
      rm "$cnf"
      substitute $cnfOrig $cnf \
        --replace 'texmf-dist' 'texmf' \
        --replace 'texmf-local' 'texmf' \
        --replace '$SELFAUTOLOC' "$out" \
        --replace '$SELFAUTODIR' "$out/share" \
        --replace '$SELFAUTOPARENT' "$out/share" \
        --replace '$SELFAUTOGRANDPARENT' "$out/share"
    }
  '' +
  # generate ls-R database
  ''
    perl $out/share/texmf/scripts/texlive/mktexlsr.pl ./share/texmf
  '' +
    # now filter hyphenation patterns
  (let
    installed = lib.concatStringsSep "|" (uniqueStrings pkgList.hyphen);
    # remove the lines for non-installed packages
    script = writeText "hyphens.pl"
      ''
        if (m/^% from (?:.*)-(.*):$/) {
          if ($1 =~ m/${installed}/) { $remove = 0; print; }
          else { $remove = 1; } }
        elsif (!$remove) { print; }
      '';
  in ''
    {
      local fname
      for fname in "$out"/share/texmf/tex/generic/config/language.{dat,def}; do
        if [[ -e "$fname" ]]; then
          local lng="$(realpath "$fname")"
          rm "$fname"
          perl -n '${script}' < "$lng" > "$fname"
        fi
      done
    }
  '') +

  # function to wrap created executables with required env vars
  ''
    wrapBin() {
    for link in ./bin/*; do
      [ -L "$link" -a -x "$link" ] || continue # if not link, assume OK
      local target=$(readlink "$link")

      # skip simple local symlinks; mktexfmt in particular
      echo "$target" | grep / > /dev/null || continue;

      echo -n "Wrapping '$link'"
      rm "$link"
      makeWrapper "$target" "$link" \
        --prefix PATH : "$out/bin:${perl}/bin" \
        --prefix PERL5LIB : "$PERL5LIB" \
        --set-default TEXMFCNF "$TEXMFCNF"

      # avoid using non-nix shebang in $target by calling interpreter
      if [[ "$(head -c 2 "$target")" = "#!" ]]; then
        local cmdline="$(head -n 1 "$target" | sed 's/^\#\! *//;s/ *$//')"
        local relative=`basename "$cmdline" | sed 's/^env //' `
        local newInterp=`echo "$relative" | cut -d\  -f1`
        local params=`echo "$relative" | cut -d\  -f2- -s`
        local newPath="$(type -P "$newInterp")"
        if [[ -z "$newPath" ]]; then
          echo " Warning: unknown shebang '$cmdline' in '$target'"
          continue
        fi
        echo " and patching shebang '$cmdline'"
        sed "s|^exec |exec $newPath $params |" -i "$link"

      elif head -n 1 "$target" | grep -q 'exec perl'; then
        # see #24343 for details of the problem
        echo " and patching weird perl shebang"
        sed "s|^exec |exec '${perl}/bin/perl' -w |" -i "$link"

      else
        sed 's|^exec |exec -a "$0" |' -i "$link"
        echo
      fi
    done
    }
  '' +
  # texlive post-install actions
  ''
    for tool in updmap; do
      ln -sf "$out/share/texmf/scripts/texlive/$tool."* "$out/bin/$tool"
    done
  '' +
    # now hack to preserve "$0" for mktexfmt
  ''
    cp "$out"/share/texmf/scripts/texlive/fmtutil.pl "$out/bin/fmtutil"
    patchShebangs "$out/bin/fmtutil"
    sed "1s|$| -I $out/share/texmf/scripts/texlive|" -i "$out/bin/fmtutil"
    ln -sf fmtutil "$out/bin/mktexfmt"

    ${bin.texlinks} "$out/bin" && wrapBin
    (perl `type -P fmtutil.pl` --sys --all || true) | grep '^fmtutil' # too verbose
    #${bin.texlinks} "$out/bin" && wrapBin # do we need to regenerate format links?

    # Disable unavailable map files
    echo y | perl `type -P updmap.pl` --sys --syncwithtrees --force
    # Regenerate the map files (this is optional)
    perl `type -P updmap.pl` --sys --force
  '' +
    # install (wrappers for) scripts, based on a list from upstream texlive
  ''
    (
      cd "$out/share/texmf/scripts"
      source '${bin.core.out}/share/texmf-dist/scripts/texlive/scripts.lst'
      for s in $texmf_scripts; do
        [[ -x "./$s" ]] || continue
        tName="$(basename $s | sed 's/\.[a-z]\+$//')" # remove extension
        [[ ! -e "$out/bin/$tName" ]] || continue
        ln -sv "$(realpath $s)" "$out/bin/$tName" # wrapped below
      done
    )
  '' +
    # A hacky way to provide repstopdf
    #  * Copy is done to have a correct "$0" so that epstopdf enables the restricted mode
    #  * ./bin/repstopdf needs to be a symlink to be processed by wrapBin
  ''
    if [[ -e ./bin/epstopdf ]]; then
      cp $(realpath ./bin/epstopdf) ./share/texmf/scripts/repstopdf
      ln -s "$out"/share/texmf/scripts/repstopdf ./bin/repstopdf
    fi
  '' +
    # finish up the wrappers
  ''
    rm "$out"/bin/*-sys
    wrapBin
  '' +
    # Perform a small test to verify that the restricted mode get enabled when
    # needed (detected by checking if it disallows --gscmd)
  ''
    if [[ -e ./bin/epstopdf ]]; then
      echo "Testing restricted mode for {,r}epstopdf"
      ! (epstopdf --gscmd echo /dev/null 2>&1 || true) | grep forbidden
      (repstopdf --gscmd echo /dev/null 2>&1 || true) | grep forbidden
    fi
  '' +
  # TODO: a context trigger https://www.preining.info/blog/2015/06/debian-tex-live-2015-the-new-layout/
    # http://wiki.contextgarden.net/ConTeXt_Standalone#Unix-like_platforms_.28Linux.2FMacOS_X.2FFreeBSD.2FSolaris.29

  # MkIV uses its own lookup mechanism and we need to initialize
  # caches for it. Unsetting TEXMFCNF is needed to let mtxrun
  # determine it from kpathsea so that the config path is given with
  # "selfautodir:" as it will be in runtime. This is important because
  # the cache is identified by a hash of this path.
  ''
    if [[ -e "$out/bin/mtxrun" ]]; then
      (
        unset TEXMFCNF
        mtxrun --generate
      )
    fi
  ''
    + bin.cleanBrokenLinks
  ;
}).overrideAttrs (_: { allowSubstitutes = true; })
# TODO: make TeX fonts visible by fontconfig: it should be enough to install an appropriate file
#       similarly, deal with xe(la)tex font visibility?
