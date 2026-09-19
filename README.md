# intel-hard

Glue that makes the locally built gen7 (Ivy Bridge, HD 4000, `8086:0166`)
drivers usable from NixOS — without replacing the system mesa.

No sources and no binaries live here. The mesa fork, clvk and their build trees
stay on the machine that builds them; this repo carries only the knowledge of
*where the ICDs are* and the NixOS plumbing to select them.

```
Drivers/                        (local, not in this repo)
  intel-hard-graphics/
    build/                      hasvk + rusticl, 64-bit
    build32/                    hasvk + rusticl, 32-bit
    build-nine/                 gallium nine, 64-bit
    build32-nine/               gallium nine, 32-bit
  clvk/build/                   clvk
  gen7-lab/                     tests

intel-hard/                     (this repo)
  graphics/  compute/  video/   which ICD sits where in the build tree
  d3d/                          gallium nine's module directory
  lib/runtime-libs.nix          libraries the drivers were linked against
  modules/nixos.nix             the NixOS module
```

## Why this works without touching the system mesa

Both loaders take their driver list from the environment:

| | variable |
|---|---|
| Vulkan | `VK_DRIVER_FILES` |
| OpenCL | `OCL_ICD_VENDORS` |
| D3D9 (wine) | `D3D_MODULE_PATH` |

All three take a list, and each loader hands a client the entry matching its
own architecture, so 32- and 64-bit builds can be exposed at once. D3D9 is
the awkward one: wine wants a *directory* holding a file called
`d3dadapter9.so.1`, and both builds want that same name, so they get a
directory each and both go on the list.

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

  # every path is derived from topology.nix, so this is usually enough
  programs.intel-hard.enable = true;
}
```

| command | environment |
|---|---|
| `ivb <cmd>` | hasvk + rusticl (+ clvk) + gallium nine |
| `ivb-vk <cmd>` | hasvk only |
| `ivb-cl <cmd>` | OpenCL only |
| `ivb-d3d <cmd>` | gallium nine only |
| `ivb-env` | print what the wrappers would set |

With no arguments each wrapper opens a shell carrying that environment.

```sh
vulkaninfo             # system driver, untouched
ivb-vk vulkaninfo      # hasvk
ivb-cl clinfo          # rusticl, clvk
ivb-d3d wine game.exe  # gallium nine, needs wine-nine-standalone
```

Gallium Nine is not part of mesa any more; it was removed in 25.2. The
frontend and the patches that carry it forward live in a separate overlay
repo, which has to be applied to the mesa fork before building:

```sh
meson setup build-nine \
  -Dgallium-drivers=crocus,softpipe -Dvulkan-drivers= \
  -Dgallium-nine=true -Dglx=dri -Dplatforms=x11
```

`softpipe` is not optional -- nine requires a swrast driver for
D3DDEVTYPE_REF, and `d3dadapter9/drm.c` opens it through
`pipe_loader_sw_probe_wrapped()`. Since the hasvk build wants neither
softpipe nor `glx=dri`, nine gets a build directory of its own and
`d3d.buildRoot` points at it; everything else keeps using `buildRoot`.

The overlay also carries four fixes that are not nine-specific and help any
gallium user on this hardware -- two crocus crashes, one `tgsi_to_nir`
miscompile, and the meson glue. They apply to the shared source tree, so the
hasvk build picks them up too.

## Known gaps

**DXVK needs `shaderInt16`, gen7 has no 16-bit integer ALU.**

With `hasvk13` and X11 WSI enabled, DXVK gets as far as enumerating the
device and then drops it:

```
info:  Found device: Intel(R) HD Graphics 4000
info:    Skipping: Device does not support required feature 'shaderInt16'
warn:  DXVK: No adapters found.
```

16-bit integers arrived with Gen8, so this is hardware, not a build option.
Lowering them to 32-bit in NIR would make DXVK proceed -- that is the piece
of work this needs, and it belongs in hasvk rather than here.

Until then D3D10/11/12 titles have no Vulkan path on this hardware; only
D3D9 does, through gallium nine.

**The 32-bit build needs two things the 64-bit one gets for free.** meson
wants `rustc` as a language whenever rusticl is on, and it looks for clang
beside llvm -- which is a separate derivation in nixpkgs. The 64-bit shell
happens to cover the second through `LIBRARY_PATH` in `commonShellVars`; the
i686 shell had neither, so it failed first with
`Unknown compiler(s): [['rustc']]` and then with `clangBasic not found`.
Both now live in the i686 shell of the mesa fork's `flake.nix`. rusticl also
keeps CLC on even at `-Dmesa-clc=system`, so the 32-bit build borrows the
64-bit `mesa_clc` and `vtn_bindgen2` through `PATH`.

Note also that WSI is not automatic: the mesa fork must be built with
`-Dplatforms=x11,wayland`. Proton runs under XWayland and wine's
`VK_KHR_win32_surface` is backed by the host's `VK_KHR_xlib_surface`, so a
Wayland-only build fails at `vkCreateInstance` before DXVK ever sees the
device.

## Options

| option | default |
|---|---|
| `buildRoot` | — (required) |
| `pciId` | `8086:0166` |
| `vulkan.driver` | `hasvk13` (also: `hasvk`, the 1.0 ICD) |
| `vulkan.buildRoot32` | `topology.driver.build32` |
| `d3d.buildRoot` | `topology.driver.buildNine` |
| `d3d.buildRoot32` | `topology.driver.build32Nine` |
| `opencl.rusticlDrivers` | `crocus` |
| `opencl.clvkBuildRoot` | `null` |
| `opencl.pocl` | `false` |

`buildRoot` is a string rather than a path on purpose — `types.path` would copy
the entire multi-gigabyte build tree into the nix store on every rebuild.
