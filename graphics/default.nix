# Vulkan ICDs
#
# meson names the ICD after the target architecture, so each driver carries
# both spellings; the module picks per build directory.
{
  hasvk13 = {
    description = "hasvk, Vulkan 1.3";
    icd = "src/intel/vulkan_hasvk/intel_hasvk13_devenv_icd.x86_64.json";
    icd32 = "src/intel/vulkan_hasvk/intel_hasvk13_devenv_icd.i686.json";
    library = "src/intel/vulkan_hasvk/libvulkan_intel_hasvk13.so";
  };

  hasvk = {
    description = "hasvk, Vulkan 1.0";
    icd = "src/intel/vulkan_hasvk/intel_hasvk_devenv_icd.x86_64.json";
    icd32 = "src/intel/vulkan_hasvk/intel_hasvk_devenv_icd.i686.json";
    library = "src/intel/vulkan_hasvk/libvulkan_intel_hasvk.so";
  };
}
