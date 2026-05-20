# dev.unmango.cmd spec feedback

Sourced from Go implementation experience. Each item describes observed friction and a concrete suggestion.

## 1. `args` semantics ambiguous (high impact)

`Process` has separate `path` and `args`. In POSIX argv, `args[0]` is conventionally the program name. The Go implementation maps `args` directly to `exec.Cmd.Args`, meaning callers must include argv[0] in `args` — but this is not obvious.

**Options:**
- Rename `args` to `argv` and document that `argv[0]` is the program name
- OR define `args` as arguments only (no argv[0]) and have implementations prepend `path` as argv[0]

The second option is less surprising for most callers.

## 2. `Exec` is output-only

`Exec` is server-streaming, so stdin is impossible. Interactive processes (shells, REPLs) are completely unsupported.

**Suggestion:** Add bidirectional streaming variant, or add `stdin: bytes` to `ExecRequest` for non-interactive stdin (piped input known upfront).

## 3. `Start` stdio is undefined

Spec does not define where stdout/stderr go for a background process started with `Start`. Implementations will vary (inherit server stdio, discard, etc.).

**Suggestion:** Either require `stdio` config on `StartRequest`, or define an explicit default (e.g., discard). The `Process.stdio` field exists but its handling for background processes is unspecified.

## 4. `Run` has no stdin

`RunRequest` contains a `Process` with `stdio.stdin`, but `Run` is a unary RPC — stdin cannot be streamed. Only `Stream_File_case` is usable. Inline stdin bytes are impossible.

**Suggestion:** Add `stdin: bytes` directly to `RunRequest` for providing stdin content in the request body.

## 5. `Wait` has no timeout

`WaitRequest` has no timeout or deadline field. Blocking wait on a hung process will block the RPC indefinitely.

**Suggestion:** Add `timeout: google.protobuf.Duration` to `WaitRequest`.

## 6. Exit code inconsistency

`RunResponse` has `exit_code: int32` directly. `ExecResponse` wraps it in `ExitResult { code: int32 }`. No reason for the inconsistency.

**Suggestion:** Pick one pattern and apply it everywhere. `ExitResult` as a message is more extensible (can add signal info, etc.) — prefer it.

## 7. `terminal: bool` is too coarse

PTY allocation requires at minimum terminal dimensions. A bool can't carry rows/cols.

**Suggestion:** Change `terminal: bool` to `terminal: Terminal` where:
```proto
message Terminal {
  uint32 rows = 1;
  uint32 cols = 2;
}
```
Presence of the field indicates PTY allocation. Absence means no PTY.

## 8. `ConversionService` type URL friction (low impact)

`ArgsRequest.spec` is `google.protobuf.Any`, requiring callers to pack their message. This is standard proto but adds a step. No obvious improvement without changing the API design fundamentally. Document the expected packing pattern in the proto comments.
