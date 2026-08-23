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

  runtimeLibPath = lib.makeLibraryPath (import ../lib/runtime-libs.nix pkgs);

  vk = graphics.${cfg.vulkan.driver};
  rusticl = compute.rusticl;

  prelude = ''
    if [ ! -d "${cfg.buildRoot}" ]; then
      echo "intel-hard: mesa build tree not found: ${cfg.buildRoot}" >&2
      echo "  build it first, or set programs.intel-hard.buildRoot" >&2
      exit 1
    fi
    export LD_LIBRARY_PATH="${runtimeLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';

  vulkanEnv = ''
    _icd="${cfg.buildRoot}/${vk.icd}"
    if [ ! -f "$_icd" ]; then
      echo "intel-hard: ${cfg.vulkan.driver} ICD not found: $_icd" >&2
      exit 1
    fi
    export VK_DRIVER_FILES="$_icd"
    export VK_ICD_FILENAMES="$_icd"
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
      # rusticl.icd names a soname, not a path.
      export LD_LIBRARY_PATH="${cfg.buildRoot}/${rusticl.libraryDir}:$LD_LIBRARY_PATH"
    else
      rm -f "$_vendors/rusticl.icd"
      echo "intel-hard: rusticl.icd not found: $_rusticl" >&2
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
      (wrapper "ivb" (vulkanEnv + openclEnv))
      (wrapper "ivb-vk" vulkanEnv)
      (wrapper "ivb-cl" (lib.optionalString (cfg.opencl.clvkBuildRoot != null) vulkanEnv + openclEnv))

      (pkgs.writeShellScriptBin "ivb-env" (
        prelude
        + vulkanEnv
        + openclEnv
        + ''
          for v in VK_DRIVER_FILES MESA_VK_DEVICE_SELECT OCL_ICD_VENDORS \
                   RUSTICL_ENABLE LD_LIBRARY_PATH; do
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
