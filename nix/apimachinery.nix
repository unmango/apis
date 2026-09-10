# The unmango.* APIs use three types from meta/v1: OwnerReference (ownership and
# expansion chains), LabelSelector/LabelSelectorRequirement (selector
# membership), and Condition (admission and readiness reporting). Upstream ships
# one file per package, so the rest of meta/v1 comes along; pkg/runtime and
# pkg/runtime/schema are here only because meta/v1 imports them. Nothing below
# imports anything further, so this is the complete closure.
#
# The repo root is the Go module k8s.io/apimachinery, so `prefix` restores the
# leading segments the import paths expect.
{ apimachinerySrc, bufLib }:
bufLib.vendor {
  name = "apimachinery-protos";
  src = apimachinerySrc;
  prefix = "k8s.io/apimachinery";
  includes = [
    "pkg/apis/meta/v1"
    "pkg/runtime"
  ];
}
