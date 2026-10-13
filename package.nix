{ lib
, stdenv
, fetchFromGitHub
, fetchgit
, cmake
, pkg-config
, makeWrapper
, libpcap
, libev
, libnl
, python3
, bash
, coreutils
, gawk
, gnugrep
, gnused
, iproute2
, iputils
, iw
, networkmanager
, procps
, systemd
, util-linux
}:

let
  pins = {
    owlRev = "832d70f815c3d4a06a02117bf0fc5e868daa1ff0";
    owlHash = "sha256-wke+tR6E4mfmzlGw1tgXiYOkSxeIRvaOmOYNWXIUVR8=";
    omdropAwdlRev = "534f91a525337951ca19c311e53d333bd6d55100";
    omdropAwdlHash = "sha256-GqxaM/5Qnj458AQPdHp1Jyfa6HK7tdybO6xDBbKUWc4=";
  };

  owlSrc = fetchgit {
    url = "https://github.com/jedbillyb/owl.git";
    rev = pins.owlRev;
    fetchSubmodules = true;
    sha256 = pins.owlHash;
  };

  omdropAwdlSrc = fetchFromGitHub {
    owner = "brentkearney";
    repo = "omdrop-awdl";
    rev = pins.omdropAwdlRev;
    hash = pins.omdropAwdlHash;
  };

  owl = stdenv.mkDerivation {
    pname = "owl";
    version = "0.1.0";
    src = owlSrc;

    patches = [
      ./patches/owl-01-tx-rate.patch
      ./patches/owl-02-awdl-addr.patch
      ./patches/owl-03-fixed-radio.patch
      ./patches/owl-04-election-metric.patch
      ./patches/owl-05-fixed-radio-noack.patch
      ./patches/owl-06-fixed-radio-pin.patch
      ./patches/owl-07-intel-reliability.patch
      ./patches/owl-08-amsdu-bound.patch
    ];

    nativeBuildInputs = [ cmake pkg-config ];
    buildInputs = [ libpcap libev libnl ];

    cmakeFlags = [
      "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    ];

    postPatch = ''
      substituteInPlace CMakeLists.txt \
        --replace-fail "add_subdirectory(googletest)" "" \
        --replace-fail "add_subdirectory(tests)" ""
    '';

    meta = {
      description = "Open Apple Wireless Direct Link (AWDL) implementation";
      homepage = "https://github.com/jedbillyb/owl";
      license = lib.licenses.gpl3Plus;
    };
  };

  pythonEnv = python3.withPackages (ps: with ps; [
    dbus-python
    pygobject3
    pillow
    libarchive-c
    zeroconf
    ifaddr
  ]);

  runtimeDeps = [
    bash
    coreutils
    gawk
    gnugrep
    gnused
    iproute2
    iputils
    iw
    networkmanager
    procps
    systemd
    util-linux
    pythonEnv
  ];

in
stdenv.mkDerivation (finalAttrs: {
  pname = "omdrop-owl";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper pythonEnv ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # Exercise files both as executables and through the interpreter used by
    # the supervisor/sender, including imports of the sibling modules.
    for script in airdrop-send.py awdl-airdrop-adv.py ble-airdrop-adv.py; do
      "$out/lib/omdrop/$script" --help >/dev/null
      ${pythonEnv}/bin/python3 "$out/lib/omdrop/$script" --help >/dev/null
    done
    "$out/bin/send-to-peer" --help >/dev/null
    PYTHONPATH="$out/lib/omdrop" ${pythonEnv}/bin/python3 -c \
      'import awdl_identity, awdl_debug, dbus, gi, PIL, libarchive, zeroconf, ifaddr'
    "$out/bin/omdrop-discoverable" status --json
    runHook postInstallCheck
  '';

  installPhase = ''
    runHook preInstall

    local libdir="$out/lib/omdrop"
    mkdir -p "$libdir" "$out/bin" "$out/share/polkit-1/actions" "$out/lib/NetworkManager/conf.d" "$out/share/doc/omdrop-owl"

    # Install OWL binary
    cp "${owl}/bin/owl" "$libdir/owl"

    # Install omdrop-awdl tools
    for f in send-to-peer airdrop-send.py awdl-af-parse.py awdl_identity.py awdl_debug.py ble-airdrop-adv.py awdl-airdrop-adv.py awdl-mdns-respond.py; do
      cp "${omdropAwdlSrc}/userspace/$f" "$libdir/$f"
    done

    # Install userspace files
    cp userspace/omdrop-discoverable "$libdir/omdrop-discoverable"
    cp userspace/owl-profiles "$libdir/owl-profiles"

    # Set permissions
    chmod +x "$libdir"/send-to-peer "$libdir"/omdrop-discoverable "$libdir"/owl "$libdir"/*.py

    # Patch shebangs in libdir to use pythonEnv and bash
    patchShebangs "$libdir"

    # Wrap omdrop-discoverable and send-to-peer to find runtime dependencies
    wrapProgram "$libdir/omdrop-discoverable" \
      --prefix PATH : "${lib.makeBinPath runtimeDeps}"

    wrapProgram "$libdir/send-to-peer" \
      --prefix PATH : "${lib.makeBinPath runtimeDeps}"

    # Keep Python files as Python: callers use python3 file.py and import
    # awdl_identity/awdl_debug. Shell wrappers break both entry points.

    # Link main executables into bin/
    ln -s "$libdir/omdrop-discoverable" "$out/bin/omdrop-discoverable"
    ln -s "$libdir/send-to-peer" "$out/bin/send-to-peer"
    ln -s "$libdir/owl" "$out/bin/owl"

    # Polkit policy (annotate both canonical store path and /usr/lib fallback)
    substitute packaging/omdrop-owl.policy "$out/share/polkit-1/actions/io.github.t4t5.omdrop-owl.policy" \
      --replace-fail "/usr/lib/omdrop/omdrop-discoverable" "$libdir/omdrop-discoverable"

    # pkexec matches the invoked path, including the legacy path used by omdrop.
    substitute packaging/omdrop-owl.policy "$out/share/polkit-1/actions/io.github.t4t5.omdrop-owl-usr.policy" \
      --replace-fail 'id="io.github.t4t5.omdrop-owl.discover"' 'id="io.github.t4t5.omdrop-owl.discover-usr"'

    # Also install NetworkManager config
    cp packaging/99-omdrop-owl-unmanaged.conf "$out/lib/NetworkManager/conf.d/99-omdrop-owl-unmanaged.conf"
    cp README.md "$out/share/doc/omdrop-owl/README.md"

    runHook postInstall
  '';

  meta = {
    description = "AirDrop radio backend for omdrop on non-Broadcom Wi-Fi using OWL";
    homepage = "https://github.com/t4t5/omdrop-owl";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "omdrop-discoverable";
  };
})
