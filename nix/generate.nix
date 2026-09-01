{
  bufLib,
  protoc-gen-go,
  workspace,
}:
bufLib.generate {
  name = "generated";

  # The workspace root, so the vendored modules are generated alongside the
  # unmango.* APIs and the go_package prefix managed mode writes into their
  # imports resolves to real packages.
  src = workspace;

  # Mirrors buf.gen.yaml, which stays in-tree for `buf generate` outside nix.
  template = bufLib.mkTemplate {
    managed = {
      enabled = true;
      override = [
        {
          file_option = "go_package_prefix";
          value = "github.com/unmango/apis/go";
        }
      ];
    };

    plugins = [
      {
        package = protoc-gen-go;
        out = "go";
        opt = [ "paths=source_relative" ];
      }
    ];
  };
}
