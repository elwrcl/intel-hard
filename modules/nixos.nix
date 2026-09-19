{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.intel-hard;
  topology = import ../topology.nix (lib.optionalAttrs (cfg.root != null) { root = cfg.root; });

  graphics = import ../graphics;
  compute = import ../compute;
  d3d = import ../d3d;

  runtimeLibPath = lib.makeLibraryPath (import ../lib/runtime-libs.nix pkgs);

  vk = graphics.${cfg.vulkan.driver};
  rusticl = compute.rusticl;
  nine = d3d.nine;


  prelude = ''
    if [ ! -d "${cfg.buildRoot}" ]; then
      echo "intel-hard: mesa build tree not found: ${cfg.buildRoot}" >&2
      echo "  build it first, or set programs.intel-hard.buildRoot" >&2
      exit 1
    fi
    export LD_LIBRARY_PATH="${runtimeLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';

  # The loader accepts several ICDs and picks the one matching the client's
  # architecture, so a 32-bit build can simply be appended.
  vulkanEnv = ''
    _icds="${cfg.buildRoot}/${vk.icd}"
    if [ ! -f "$_icds" ]; then
      echo "intel-hard: ${cfg.vulkan.driver} ICD not found: $_icds" >&2
      exit 1
    fi
  ''
  + lib.optionalString (cfg.vulkan.buildRoot32 != null) ''
    _icd32="${cfg.vulkan.buildRoot32}/${vk.icd32}"
    if [ -f "$_icd32" ]; then
      _icds="$_icds:$_icd32"
    fi
  ''
  + ''
    export VK_DRIVER_FILES="$_icds"
    export VK_ICD_FILENAMES="$_icds"
    export MESA_VK_DEVICE_SELECT="${cfg.pciId}"

    # A system-wide MESA_GL_VERSION_OVERRIDE=4.6 lies about the GL version.
    unset MESA_GL_VERSION_OVERRIDE
  '';

  openclEnv = ''
    _vendors="''${XDG_RUNTIME_DIR:-/tmp}/intel-hard/icd-vendors"
    mkdir -p "$_vendors/lib"

    _rusticl="${cfg.buildRoot}/${rusticl.icd}"
    if [ -f "$_rusticl" ]; then
      ln -sf "$_rusticl" "$_vendors/rusticl.icd"
      # rusticl.icd names a soname, not a path, so both builds can share the
      # one .icd file: ld.so walks LD_LIBRARY_PATH and skips the library whose
      # architecture does not match the client.
      export LD_LIBRARY_PATH="${cfg.buildRoot}/${rusticl.libraryDir}:$LD_LIBRARY_PATH"
    else
      rm -f "$_vendors/rusticl.icd"
      echo "intel-hard: rusticl.icd not found: $_rusticl" >&2
    fi
  ''
  + lib.optionalString (cfg.vulkan.buildRoot32 != null) ''
    if [ -d "${cfg.vulkan.buildRoot32}/${rusticl.libraryDir}" ]; then
      export LD_LIBRARY_PATH="${cfg.vulkan.buildRoot32}/${rusticl.libraryDir}:$LD_LIBRARY_PATH"
    fi
  ''
  + lib.optionalString (cfg.opencl.clvkBuildRoot != null) ''
    _clvk_src="${cfg.opencl.clvkBuildRoot}/libOpenCL.so.1"
    if [ -f "$_clvk_src" ]; then
      _clvk_lib="$_vendors/lib/libclvk.so.1"
      if [ "$_clvk_src" -nt "$_clvk_lib" ]; then
        cp -L "$_clvk_src" "$_clvk_lib.tmp"
        chmod u+w "$_clvk_lib.tmp"
        ${pkgs.patchelf}/bin/patchelf --set-soname libclvk.so.1 "$_clvk_lib.tmp"
        mv "$_clvk_lib.tmp" "$_clvk_lib"
      fi
      echo "$_clvk_lib" > "$_vendors/clvk.icd"
    else
      rm -f "$_vendors/clvk.icd"
      echo "intel-hard: clvk not found: $_clvk_src" >&2
    fi
  ''
  + lib.optionalString cfg.opencl.pocl ''
    ln -sf ${pkgs.pocl}/etc/OpenCL/vendors/pocl.icd "$_vendors/pocl.icd"
  ''
  + ''
    export OCL_ICD_VENDORS="$_vendors"
    export OCL_ICD_ASSUME_ICD_EXTENSION=1
    export RUSTICL_ENABLE="${cfg.opencl.rusticlDrivers}"
  '';

  # wine's d3d9 loader takes a *directory*, and looks for a file literally
  # named d3dadapter9.so.1 inside it. meson leaves the versioned name in the
  # build tree, so point the loader at a directory of symlinks.
  #
  # 32- and 64-bit nine cannot share one directory: both want that same file
  # name. They get one each, and both go on D3D_MODULE_PATH -- wine walks the
  # list and skips what it cannot dlopen, so a 32-bit process lands on the
  # 32-bit build and a 64-bit one on the 64-bit build.
  d3dLink = suffix: root: ''
    _nine="${root}/${nine.library}"
    if [ -f "$_nine" ]; then
      mkdir -p "$_d3d/${suffix}"
      ln -sf "$_nine" "$_d3d/${suffix}/${nine.soname}"
      _d3d_paths="''${_d3d_paths:+$_d3d_paths:}$_d3d/${suffix}"
    fi
  '';

  d3dEnv = ''
    _d3d="''${XDG_RUNTIME_DIR:-/tmp}/intel-hard/d3d"
    _d3d_paths=
  ''
  + lib.optionalString (cfg.d3d.buildRoot != null) (d3dLink "64" cfg.d3d.buildRoot)
  + lib.optionalString (cfg.d3d.buildRoot32 != null) (d3dLink "32" cfg.d3d.buildRoot32)
  + ''
    if [ -z "$_d3d_paths" ]; then
      echo "intel-hard: gallium nine not found" >&2
      echo "  build mesa with -Dgallium-nine=true -Dgallium-drivers=crocus,softpipe -Dglx=dri" >&2
      echo "  then set programs.intel-hard.d3d.buildRoot (and .buildRoot32)" >&2
      exit 1
    fi
    export D3D_MODULE_PATH="$_d3d_paths"
  '';

  run = ''
    if [ $# -eq 0 ]; then
      exec "''${SHELL:-${pkgs.bashInteractive}/bin/bash}"
    fi
    exec "$@"
  '';

  wrapper = name: body: pkgs.writeShellScriptBin name (prelude + body + run);
in
{
  options.programs.intel-hard = {
    enable = lib.mkEnableOption "the locally built gen7 (Ivy Bridge) drivers";

    root = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/mnt/HDD/linuxdata/Projects/Drivers";
      description = "Directory holding the driver trees. Null uses topology.nix's default.";
    };

    buildRoot = lib.mkOption {
      type = lib.types.str;
      default = topology.driver.build;
      defaultText = "topology.driver.build";
      description = "Meson build directory of the mesa fork.";
    };

    pciId = lib.mkOption {
      type = lib.types.str;
      default = "8086:0166";
      description = "PCI ID for the IVB HD 4000.";
    };

    vulkan.driver = lib.mkOption {
      type = lib.types.enum (lib.attrNames graphics);
      default = "hasvk13";
      description = "Which hasvk ICD the Vulkan wrappers select.";
    };

    vulkan.buildRoot32 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = topology.driver.build32;
      defaultText = "topology.driver.build32";
      description = ''
        Meson build directory of the 32-bit driver, or null to leave it out.
        Its ICD is appended to VK_DRIVER_FILES; the loader hands each client
        the ICD matching its own architecture.
      '';
    };

    d3d.buildRoot = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = topology.driver.buildNine;
      defaultText = "topology.driver.buildNine";
      description = ''
        Meson build directory holding the 64-bit gallium nine, or null to
        leave it out. Nine needs softpipe and glx=dri, which the hasvk build
        does not enable, so it sits in a build directory of its own.
      '';
    };

    d3d.buildRoot32 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = topology.driver.build32Nine;
      defaultText = "topology.driver.build32Nine";
      description = ''
        Same, for the 32-bit nine. Most D3D9 titles are 32-bit, so this is
        usually the one that matters.
      '';
    };

    opencl.rusticlDrivers = lib.mkOption {
      type = lib.types.str;
      default = "crocus";
      description = "RUSTICL_ENABLE value. Without it rusticl exposes no device.";
    };

    opencl.clvkBuildRoot = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = topology.clvk.build;
      defaultText = "topology.clvk.build";
      description = "clvk build directory, or null to leave clvk out.";
    };

    opencl.pocl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Also expose pocl, as a CPU reference implementation.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (wrapper "ivb" (vulkanEnv + openclEnv + d3dEnv))
      (wrapper "ivb-vk" vulkanEnv)
      (wrapper "ivb-cl" (lib.optionalString (cfg.opencl.clvkBuildRoot != null) vulkanEnv + openclEnv))
      (wrapper "ivb-d3d" d3dEnv)

      (pkgs.writeShellScriptBin "ivb-env" (
        prelude
        + vulkanEnv
        + openclEnv
        + d3dEnv
        + ''
          for v in VK_DRIVER_FILES MESA_VK_DEVICE_SELECT OCL_ICD_VENDORS \
                   RUSTICL_ENABLE D3D_MODULE_PATH LD_LIBRARY_PATH; do
            printf '%s=%s\n' "$v" "''${!v-}"
          done
          echo
          echo "OpenCL platforms:"
          ls "$OCL_ICD_VENDORS"/*.icd 2>/dev/null | xargs -rn1 basename || echo "  (none)"
        ''
      ))
    ];
  };
}
