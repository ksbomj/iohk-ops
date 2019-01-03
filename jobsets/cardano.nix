let
  fixedNixpkgs = (import ../lib.nix).fetchNixPkgs;
in { pkgs ? (import fixedNixpkgs {})
   , supportedSystems ? [ "x86_64-linux" "x86_64-darwin" ]
   , scrubJobs ? true
   }:

with import (fixedNixpkgs + "/pkgs/top-level/release-lib.nix") { inherit supportedSystems scrubJobs; packageSet = import ../.; };

let
  iohkpkgs = import ./../default.nix { inherit pkgs; };
  nix-darwin-tools = import ../nix-darwin;
  jobs = mapTestOn ((packagePlatforms iohkpkgs) // {
    iohk-ops = [ "x86_64-linux" ];
    github-webhook-util = [ "x86_64-linux" ];
    iohk-ops-integration-test = [ "x86_64-linux" ];
    nixops = [ "x86_64-linux" ];
  });
  cardanoSrc = pkgs.fetchgit cardano-sl-src;
  cardano-sl-src = builtins.fromJSON (builtins.readFile ./../cardano-sl-src.json);
  cardanoRelease = import "${cardanoSrc}/release.nix" {
    cardano = {
      outPath = cardanoSrc;
      rev = cardano-sl-src.rev;
    };
  };
  tests = import ../tests {
    inherit pkgs;
    supportedSystems = [ "x86_64-linux" ];
  };
in pkgs.lib.fix (jobsets: {
  inherit (jobs) iohk-ops iohk-ops-integration-test nixops;
  inherit (iohkpkgs) checks;
  inherit tests cardanoRelease nix-darwin-tools;
  required = pkgs.lib.hydraJob (pkgs.releaseTools.aggregate {
    name = "iohk-ops-required-checks";
    constituents =
      let
        all = x: map (system: x.${system}) supportedSystems;
    in [
      jobsets.nix-darwin-tools.tools
      jobsets.iohk-ops.x86_64-linux
      (pkgs.lib.collect (x : x ? outPath) jobsets.cardanoRelease)
      (builtins.attrValues jobsets.tests)
      (builtins.attrValues jobsets.checks)
    ];
  });
})
