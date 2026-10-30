{
  perSystem =
    {
      pkgs,
      go,
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        packages = [
          go
          pkgs.go-jsonnet
          pkgs.grpcurl
        ];
      };
      formatter = pkgs.nixfmt-tree;
    };
}
