# intel-hard

Glue that makes the locally built gen7 (Ivy Bridge, HD 4000, `8086:0166`)
drivers usable from NixOS — without replacing the system mesa.

No sources and no binaries live here. The mesa fork, clvk and their build trees
stay on the machine that builds them; this repo carries only the knowledge of
*where the ICDs are* and the NixOS plumbing to select them.

```
Drivers/                        (local, not in this repo)
  intel-hard-graphics/build/    hasvk + rusticl, built with meson
  clvk/build/                   clvk
  gen7-lab/                     tests

intel-hard/                     (this repo)
  graphics/  compute/  video/   which ICD sits where in the build tree
  lib/runtime-libs.nix          libraries the drivers were linked against
  modules/nixos.nix             the NixOS module
```

## Why this works without touching the system mesa

Both loaders take their driver list from the environment:

| | variable |
|---|---|
| Vulkan | `VK_DRIVER_FILES` |
| OpenCL | `OCL_ICD_VENDORS` |

So an extra driver needs no system file, no `hardware.graphics` change and no
mesa replacement — just an environment. The module ships that environment as
wrapper commands.

Because the ICD JSON points into the build tree, `ninja` is enough to pick up a
driver change. No `nixos-rebuild`.

## Usage

```nix
{
  inputs.intel-hard.url = "github:elwrcl/intel-hard";

  # in the NixOS configuration
  imports = [ inputs.intel-hard.nixosModules.default ];

  programs.intel-hard = {
    enable = true;
    buildRoot = "/mnt/HDD/linuxdata/Projects/Drivers/intel-hard-graphics/build";
    opencl.clvkBuildRoot = "/mnt/HDD/linuxdata/Projects/Drivers/clvk/build";
  };
}
```

| command | environment |
|---|---|
| `ivb <cmd>` | hasvk + rusticl (+ clvk) |
| `ivb-vk <cmd>` | hasvk only |
| `ivb-cl <cmd>` | OpenCL only |
| `ivb-env` | print what the wrappers would set |

With no arguments each wrapper opens a shell carrying that environment.

```sh
vulkaninfo             # system driver, untouched
ivb-vk vulkaninfo      # hasvk
ivb-cl clinfo          # rusticl, clvk
```

## Options

| option | default |
|---|---|
| `buildRoot` | — (required) |
| `pciId` | `8086:0166` |
| `vulkan.driver` | `hasvk13` (also: `hasvk`, the 1.0 ICD) |
| `opencl.rusticlDrivers` | `crocus` |
| `opencl.clvkBuildRoot` | `null` |
| `opencl.pocl` | `false` |

`buildRoot` is a string rather than a path on purpose — `types.path` would copy
the entire multi-gigabyte build tree into the nix store on every rebuild.
