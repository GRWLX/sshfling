{
  description = "SSHFling temporary SSH access broker and CLI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          nativeRuntimePath = [
            pkgs.coreutils
            pkgs.gawk
            pkgs.gnused
            pkgs.bash
            pkgs.jq
          ]
            ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.shadow
              pkgs.procps
              pkgs.util-linux
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.flock ];
          runtimePath = nativeRuntimePath ++ [ pkgs.python3 pkgs.openssh pkgs.openssl ];
        in {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "sshfling";
            version = "0.1.16";
            src = self;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            dontPatchShebangs = true;
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              install -Dm755 bin/sshfling $out/bin/sshfling
              install -Dm755 native/sshfling-linux-account $out/libexec/sshfling/sshfling-linux-account
              install -Dm755 native/sshfling-unix-identity $out/libexec/sshfling/sshfling-unix-identity
              install -Dm755 production/sshfling-login-shell $out/share/sshfling/templates/production/sshfling-login-shell
              install -Dm755 production/sshfling-session $out/share/sshfling/templates/production/sshfling-session
              install -Dm644 LICENSE $out/share/doc/sshfling/LICENSE
              install -Dm644 README.md $out/share/doc/sshfling/README.md
              mkdir -p $out/share/sshfling/templates
              cp -a .env.example LICENSE README.md compose.server.yml compose.client.yml native scripts secrets ssh-client ssh-server production systemd $out/share/sshfling/templates/
              substituteInPlace $out/share/sshfling/templates/production/sshfling-session \
                --replace-fail \
                  'session_user_path="''${PATH:-}"' \
                  'session_user_path="${pkgs.lib.makeBinPath nativeRuntimePath}:''${PATH:-}"' \
                --replace-fail \
                  'PATH="/usr/sbin:/usr/bin:/sbin:/bin:' \
                  'PATH="${pkgs.lib.makeBinPath nativeRuntimePath}:/usr/sbin:/usr/bin:/sbin:/bin:'
              patchShebangs $out/share/sshfling/templates/production/sshfling-session
              patchShebangs $out/bin/sshfling
              patchShebangs $out/libexec/sshfling/sshfling-linux-account
              patchShebangs $out/libexec/sshfling/sshfling-unix-identity
              wrapProgram $out/libexec/sshfling/sshfling-linux-account \
                --set SSHFLING_NATIVE_TOOL_PATH ${pkgs.lib.makeBinPath nativeRuntimePath}
              wrapProgram $out/libexec/sshfling/sshfling-unix-identity \
                --set SSHFLING_NATIVE_TOOL_PATH ${pkgs.lib.makeBinPath nativeRuntimePath}
              wrapProgram $out/bin/sshfling \
                --prefix PATH : ${pkgs.lib.makeBinPath runtimePath} \
                --set SSHFLING_NATIVE_TOOL_PATH ${pkgs.lib.makeBinPath nativeRuntimePath} \
                --set SSHFLING_LINUX_ACCOUNT_HELPER $out/libexec/sshfling/sshfling-linux-account \
                --set SSHFLING_UNIX_IDENTITY_HELPER $out/libexec/sshfling/sshfling-unix-identity
              runHook postInstall
            '';
            meta = with pkgs.lib; {
              description = "Temporary SSH access broker and CLI";
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
