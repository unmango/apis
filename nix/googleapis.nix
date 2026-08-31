# google/type and google/api/field_behavior.proto are the only parts of
# googleapis the unmango.* APIs import, and their closure reaches nothing
# outside the well-known types buf already provides: field_behavior.proto
# imports only google/protobuf/descriptor.proto.
{ bufLib, googleapisSrc }:
bufLib.vendor {
  name = "googleapis-type-protos";
  src = googleapisSrc;
  includes = [
    "google/type"
    "google/api/field_behavior.proto"
  ];
}
