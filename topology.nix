{
  root ? "/mnt/HDD/linuxdata/Projects_XFS/Drivers",
}:

rec {
  inherit root;

  names = {
    driver = "intel-hard-graphics";    # elwrcl/intel-hard-graphics
    lab = "intel-hard-lab";            # elwrcl/intel-hard-lab
    clvk = "clvk";                     # elwrcl/clvk (fork)
    cts = "VK-GL-CTS";                 # elwrcl/VK-GL-CTS (fork)
  };

  driver = rec {
    src = "${root}/${names.driver}";

    # hasvk + rusticl
    build = "${src}/build";
    build32 = "${src}/build32";

    # gallium nine wants softpipe and glx=dri, which the build above does
    # not enable, so it gets meson directories of its own.
    buildNine = "${src}/build-nine";
    build32Nine = "${src}/build32-nine";
  };

  clvk = rec {
    src = "${root}/${names.clvk}";
    build = "${src}/build";
  };

  cts = rec {
    src = "${root}/${names.cts}";
    build = "${src}/build-cts";
    deqp = "${build}/external/vulkancts/modules/vulkan";
    mustpass = "${src}/external/vulkancts/mustpass/main/vk-default";
  };

  lab = "${root}/${names.lab}";

  pins = {
    clvk = "0ebfb2039152815a5b4db02d46f9313a3e7b72df";  # 2026-07-07
    cts = "68a4b00fbd81e480d70568f3095cc0be93d03836";   # 2026-07-07
  };
}
