{
  description = "Fast, disposable Git worktrees for AI agents and throwaway experiments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          temptree = pkgs.stdenvNoCC.mkDerivation {
            pname = "temptree";
            version = "0.1.0";
            src = ./.;

            nativeBuildInputs = [ pkgs.makeWrapper ];

            installPhase = ''
              install -Dm755 temptree $out/bin/temptree
              install -Dm755 rmtree $out/bin/rmtree

              wrapProgram $out/bin/temptree --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.git pkgs.coreutils ]}
              wrapProgram $out/bin/rmtree --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.git pkgs.coreutils ]}

              install -Dm644 shell_helpers.sh $out/share/temptree/shell_helpers.sh
              install -Dm644 fish_helpers.fish $out/share/temptree/fish_helpers.fish
              install -Dm644 nushell_helpers.nu $out/share/temptree/nushell_helpers.nu
            '';

            meta = with pkgs.lib; {
              description = "Fast, disposable Git worktrees for AI agents and throwaway experiments";
              license = licenses.mit;
              platforms = platforms.unix;
            };
          };
        in
        {
          inherit temptree;
          default = temptree;
        }
      );

      overlays.default = final: prev: {
        temptree = self.packages.${final.system}.temptree;
      };
    };
}
