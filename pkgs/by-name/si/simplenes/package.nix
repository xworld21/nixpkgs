{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  sfml,
}:

stdenv.mkDerivation {
  pname = "simplenes";
  version = "unstable-2019-03-13";

  src = fetchFromGitHub {
    owner = "amhndu";
    repo = "SimpleNES";
    rev = "4edb7117970c21a33b3bfe11a6606764fffc5173";
    sha256 = "1nmwj431iwqzzcykxd4xinqmg0rm14mx7zsjyhcc5skz7pihz86g";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ sfml ];

  installPhase = ''
    mkdir -p $out/bin
    cp ./SimpleNES $out/bin
  '';

  meta = with lib; {
    homepage = "https://github.com/amhndu/SimpleNES";
    description = "NES emulator written in C++";
    license = licenses.gpl3;
    maintainers = [ ];
    platforms = platforms.linux;
    mainProgram = "SimpleNES";
  };
}
