# OpenCL ICDs
{
  rusticl = {
    description = "rusticl on crocus";
    icd = "src/gallium/targets/rusticl/rusticl.icd";
    library = "src/gallium/targets/rusticl/libRusticlOpenCL.so.1";

    # rusticl.icd names the soname only not a path.
    libraryDir = "src/gallium/targets/rusticl";
  };
}
