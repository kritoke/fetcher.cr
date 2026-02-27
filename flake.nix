{
  description = "fetcher.cr Spoke - crystal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    openspec.url = "github:Fission-AI/OpenSpec";
  };

  outputs = { self, nixpkgs, openspec }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Allow developers to provide a private flake override for ticket (not committed).
      # Developer-provided `flake.private.nix` may be a shell script, a Nix attrset,
      # or a flake (with `outputs`). Importing blindly can cause evaluation errors
      # if the file isn't a plain Nix attrset. We attempt a safe import strategy:
      # 1) If the file looks like a shell script (starts with #!), ignore it.
      # 2) Try importing with arguments (`{ inherit pkgs; }`). If that succeeds use it.
      # 3) Try importing without args. If that succeeds and is not a flake (no `outputs`), use it.
      # 4) Otherwise fall back to an empty set.
      private =
        if builtins.pathExists ./flake.private.nix then
          let
            content = builtins.readFile ./flake.private.nix;
            try_with_args = builtins.tryEval (import ./flake.private.nix { inherit pkgs; });
            try_no_args = builtins.tryEval (import ./flake.private.nix);
          in
            if builtins.substring 0 2 content == "#!" then {}
            else if try_with_args.success then try_with_args.value
            else if try_no_args.success then (if try_no_args.value ? outputs then {} else try_no_args.value)
            else {}
        else {};

      # Prefer private.ticket from flake.private.nix; do not create a public ticket derivation here.
      # The developer should provide `ticket` in their local `flake.private.nix` if desired.
      ticket = if private ? ticket then private.ticket else null;

      # Path to add to the shell's PATH; empty string if ticket is not present.
      ticketPath = if builtins.isNull ticket then "" else "${ticket}/bin";

      # Allow private flake to provide a `shellHook` fragment for local env setup.
      privateShellHook = if private ? shellHook then private.shellHook else "";

      # Common minimal shellHook and optional private fragment are computed here
      # so they can be referenced when building the mkShell attributes below.
      commonShell = ''
        echo "fetcher.cr DevShell Active"
        export PATH="$PATH:${ticketPath}"
      '';

      privateShell = if builtins.stringLength privateShellHook == 0 then "" else privateShellHook;

      # Prefer the nixpkgs-provided Crystal 1.18 package when available.
      # Many nixpkgs provide `crystal_1_18` for stable older Crystal releases.
      # Fall back to `pkgs.crystal` if the specific attr is not present.
      crystal_1_18 = if builtins.hasAttr "crystal_1_18" pkgs then pkgs.crystal_1_18 else pkgs.crystal;

      # System-specific Xorg libraries for Playwright
      # The `xorg` attribute set is deprecated in nixpkgs; prefer modern attribute names.
      # Map legacy names (libX...) to modern names (libx...) and try both.
      getXorg = name:
        let alt = builtins.replaceStrings [ "libX" ] [ "libx" ] name;
        in if builtins.hasAttr alt pkgs then builtins.getAttr alt pkgs else if builtins.hasAttr name pkgs then builtins.getAttr name pkgs else null;

      # Playwright libs removed from default spoke; include only when explicitly requested in a module.
      pwLibs = with pkgs; [];
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [ crystal_1_18 ] ++ pwLibs;

        # Minimal, portable shellHook. Local, developer-specific setup (SSH agent bridging,
        # HUB_ROOT overrides, etc.) should live in ./flake.private.nix as `shellHook`.
        shellHook = commonShell + privateShell;
      };
    };
}
