{
  lib,
  stdenvNoCC,
  substituteAll,
  freebuff-desktop,
}:

stdenvNoCC.mkDerivation {
  pname = "freebuff-desktop-wrapper";
  inherit (freebuff-desktop) version;

  phases = ["installPhase"];

  installPhase = ''
    mkdir -p $out/bin
    sed -e 's|@version@|${freebuff-desktop.version}|g' \
        ${../wrapper/freebuff-desktop.sh} > $out/bin/freebuff-desktop
    chmod +x $out/bin/freebuff-desktop
  '';

  meta = with lib; {
    description = "Runtime wrapper for Freebuff Desktop (GPU fixes, auto-update)";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [];
  };
}
