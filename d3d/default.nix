# Direct3D frontends
#
# Unlike the Vulkan and OpenCL loaders, wine's d3d9 loader takes a
# *directory* rather than an ICD file: wine-nine-standalone looks for
# `d3dadapter9.so.1` inside every path in D3D_MODULE_PATH.
{
  nine = {
    description = "Gallium Nine, D3D9 on crocus";

    # d3dadapter9.so.1 has to be reachable under this name, so the wrapper
    # builds a small directory of symlinks rather than pointing straight at
    # the build tree (meson leaves the versioned name there).
    moduleDir = "src/gallium/targets/d3dadapter9";
    library = "src/gallium/targets/d3dadapter9/d3dadapter9.so.1.0.0";
    soname = "d3dadapter9.so.1";
  };
}
