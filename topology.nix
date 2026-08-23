{
  root ? "/mnt/HDD/linuxdata/Projects/Drivers",
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
    build = "${src}/build";
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
