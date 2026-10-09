# Failure diagnostics

**Type: rule** (keep diagnostics) with a **default** implementation.

Look for teardown code shaped like:

```python
if request.session.testsfailed:
    log = model.debug_log(limit=1000)
```

or pytest-operator's crash-dump behavior. This is diagnostics, not lifecycle. Do not
delete it alongside `OpsTest`.

pytest-jubilant destroys the model at module teardown and dumps nothing by default.
Dropping this leaves failing CI jobs with zero Juju output — invisible locally,
because passing runs never needed it.

## Replacement

pytest-jubilant provides a log-dumping option that writes the full `juju debug-log`
per model immediately before teardown. Confirm the current flag name and default
directory in the plugin source, then wire it into the layer that runs pytest so every
run gets it:

```ini
[testenv:integration]
commands =
    pytest ... --juju-dump-logs -s {posargs}
```

Differences worth stating explicitly to the user:

| | pytest-operator teardown | plugin log dumping |
|---|---|---|
| Trigger | only when tests failed | always, when passed |
| Volume | truncated, e.g. `limit=1000` | full log |
| Destination | stdout | one file per model |
| Default | on | **off** |

If failure-only truncated stdout output is genuinely required, add a small local
hook, the same way `abort_on_fail` is preserved. Do not rebuild model management.

## Retain in CI

The example below is GitHub Actions. For another CI system, apply the same properties:
upload even on failure, unique name per parallel job, include hidden files, and warn
(not silently pass) when nothing was found.

```yaml
- name: Upload Juju debug logs
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: juju-debug-logs-${{ matrix.test }}
    path: .logs/
    include-hidden-files: true
    if-no-files-found: warn
```

- `if: always()` — the failure case is the one that needs logs
- unique name per matrix entry, or parallel jobs collide
- `include-hidden-files: true` — `.logs/` is dot-prefixed and `actions/upload-artifact`
  skips hidden files by default, so without this the step succeeds and uploads nothing
- `if-no-files-found: warn` — a job may die before any model exists, but `ignore` makes
  a silently empty artifact look identical to a working one
- place before other failure-only steps so it runs even if those fail

Three parts are all required: the flag in the committed test command, the dump
directory in `.gitignore`, and the artifact upload step. Missing any one leaves the
setup looking complete while producing nothing.

Only add the flag on a branch where `pytest-jubilant` is installed. On a
pytest-operator branch it is an unrecognized argument that fails every job before any
test runs.
