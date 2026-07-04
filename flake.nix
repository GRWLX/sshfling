{
  description = "SSHFling temporary SSH certificate issuer and access CLI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          runtimePath = [ pkgs.openssh pkgs.procps pkgs.util-linux ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.shadow ];
        in {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "sshfling";
            version = "0.1.6";
            src = self;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            installPhase = ''
              runHook preInstall
              install -Dm755 bin/sshfling $out/bin/sshfling
              install -Dm755 production/sshfling-session $out/share/sshfling/templates/production/sshfling-session
              install -Dm644 LICENSE $out/share/doc/sshfling/LICENSE
              install -Dm644 README.md $out/share/doc/sshfling/README.md
              mkdir -p $out/share/sshfling/templates
              cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml scripts secrets ssh-client ssh-server production systemd $out/share/sshfling/templates/
              patchShebangs $out/bin/sshfling
              wrapProgram $out/bin/sshfling --prefix PATH : ${pkgs.lib.makeBinPath runtimePath}
              runHook postInstall
            '';
            meta = with pkgs.lib; {
              description = "Temporary SSH certificate issuer and access CLI";
              homepage = "https://github.com/GRWLX/sshfling";
              license = licenses.asl20;
              mainProgram = "sshfling";
              platforms = platforms.unix;
            };
          };
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/sshfling";
        };
      });
    };
}
