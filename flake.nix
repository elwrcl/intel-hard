{
  description = "intel-hard — gen7-IVB driver ICDs, wired into NixOS";
  inputs = { };

  outputs =
    { self }:
    {
      nixosModules.default = ./modules/nixos.nix;
      nixosModules.intel-hard = ./modules/nixos.nix;

      lib = {
        topology = import ./topology.nix;
        graphics = import ./graphics;
        compute = import ./compute;
        video = import ./video;
        d3d = import ./d3d;
        runtimeLibs = import ./lib/runtime-libs.nix;
      };
    };
}
