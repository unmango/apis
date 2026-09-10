{ bufLib, workspace }:
bufLib.build {
  name = "apis.binpb";
  input = workspace;
}
