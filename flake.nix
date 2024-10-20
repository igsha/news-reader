{
  description = "A news reader terminal app on bash";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in {
    packages.x86_64-linux = {
      news-reader = pkgs.writeShellApplication {
        name = "news-reader";
        text = builtins.readFile ./news-reader.sh;
        runtimeInputs = with pkgs; [
          which
          parallel
          jq
          curl
          xq-xml
          pandoc
          jo
          htmlq
        ];

        meta = with pkgs.lib; {
          description = "A news reader terminal app on bash";
          homepage = "https://github.com/igsha/news-reader";
          maintainers = [ maintainers.igsha ];
          platforms = platforms.all;
          license = licenses.mit;
        };
      };
      default = self.packages.x86_64-linux.news-reader;
    };
  };
}
