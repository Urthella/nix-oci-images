{
  description = "The same Go server as an OCI image, built with four Dockerfiles and two Nix builders, measured side by side";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nix2container, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      linux = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${linux};
      n2c = nix2container.packages.${linux}.nix2container;

      # The same flags as the Dockerfiles: static, no paths baked in, no symbol table.
      hello = pkgs.buildGoModule {
        pname = "hello";
        version = "0.1.0";
        src = ./app;
        vendorHash = null;
        env.CGO_ENABLED = 0;
        ldflags = [ "-s" "-w" ];
      };
    in
    {
      packages.${linux} = {
        inherit hello;

        # nixpkgs' own builder: one layer per store path, written out as a docker-load tarball.
        image-dockertools = pkgs.dockerTools.buildLayeredImage {
          name = "hello";
          tag = "nix-dockertools";
          config = {
            Entrypoint = [ "${hello}/bin/hello" ];
            User = "65532";
            ExposedPorts."8080/tcp" = { };
          };
        };

        # nix2container: layers come straight from the store, with no tarball in between.
        image-nix2container = n2c.buildImage {
          name = "hello";
          tag = "nix-nix2container";
          config = {
            entrypoint = [ "${hello}/bin/hello" ];
            user = "65532";
            exposedPorts."8080/tcp" = { };
          };
        };
      };

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell { packages = with pkgs; [ go jq ]; };
      });
    };
}
