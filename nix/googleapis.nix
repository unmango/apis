# google/type and the three google/api annotation protos are the only parts of
# googleapis the unmango.* APIs import, and their closure reaches nothing
# outside the well-known types buf already provides: all three api protos
# import only google/protobuf/descriptor.proto.
{ bufLib, googleapisSrc }:
bufLib.vendor {
  name = "googleapis-type-protos";
  src = googleapisSrc;
  includes = [
    "google/type"
    "google/api/field_behavior.proto"
    "google/api/field_info.proto"
    "google/api/resource.proto"
  ];
}
