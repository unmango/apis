# A v2 workspace resolves imports between its own modules, so vendored protos
# replace the BSR dependency the checked-in buf.yaml declares: no buf.lock, no
# module cache, no network during the build.
{
  apimachinery,
  bufLib,
  googleapis,
}:
bufLib.mkWorkspace {
  name = "unmango-apis-workspace";

  # Module roots are the import prefixes, and buf rejects nested module paths,
  # so the vendored trees cannot share a single "third_party" root.
  modules = [
    {
      path = "third_party/googleapis";
      src = googleapis;
      vendor = true;
    }
    {
      path = "third_party/k8s";
      src = apimachinery;
      vendor = true;
    }
    {
      path = "proto";
      name = "buf.build/unmango/apis";
      src = ../proto;
    }
  ];

  lint.use = [ "STANDARD" ];
  breaking.use = [ "FILE" ];
}
