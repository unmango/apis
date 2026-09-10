# google/api-linter over the life domains, configured by ../api-linter.yaml.
#
# The infrastructure APIs are excluded rather than configured: cli, cmd,
# protofs, and discord/backup model no resource, so the resource-oriented AIPs
# have nothing to say about them. See docs/aip.md.
{
  api-linter,
  buf,
  runCommand,
  workspace,
}:
runCommand "api-linter"
  {
    nativeBuildInputs = [
      api-linter
      buf
    ];
  }
  ''
    export HOME="$(mktemp -d)"
    cp -rL ${workspace} workspace
    chmod -R u+w workspace

    # api-linter compiles editions up to 2023, and given a 2024 descriptor set
    # it reports zero files found rather than an error. Nothing in these files
    # uses a feature whose default moved between the two editions, so the
    # descriptors this produces differ from the real ones only in the edition.
    grep -rl 'edition = "2024";' workspace \
      | xargs sed -i 's/^edition = "2024";/edition = "2023";/'

    # api-linter cannot resolve the k8s.io imports on its own, and buf can, so
    # the descriptor set is built once here and linted with --skip-compilation.
    buf build workspace --as-file-descriptor-set -o descriptors.binpb

    cd workspace/proto
    api-linter \
      --skip-compilation \
      --descriptor-set-in=../../descriptors.binpb \
      --config=${../api-linter.yaml} \
      --output-format=summary \
      --set-exit-status \
      $(find unmango -name '*.proto' \
        | grep -vE '^unmango/(cli|cmd|protofs|discord)/' \
        | sort)

    touch "$out"
  ''
