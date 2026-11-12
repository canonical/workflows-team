# pytest-jubilant command-line flags

**Type: reference.** Versions change; verify before use.

**Verify against the installed version before use.** Flag names and defaults change
between releases. Check with:

```bash
pytest --help | grep -A1 juju
```

or read the plugin source:
https://github.com/canonical/pytest-jubilant/blob/main/pytest_jubilant/_main.py

These options belong to the plugin. A repository must **not** register them itself in
a local `pytest_addoption`.

## Options

| Flag | Purpose | Replaces |
|---|---|---|
| `--no-juju-teardown` | Keep models after the run instead of destroying them | `--keep-models` |
| `--no-juju-setup` | Skip `juju_setup` **tests** and model creation; requires `--juju-model` | — |
| `--juju-model` | Prefix. Model name is `{prefix}-{module}` (`_` becomes `-`) | `--model` reuse |
| `--juju-dump-logs` | Full `juju debug-log` before teardown (default `./.logs`). Optional path argument | failure-time `debug_log` in teardown |
| `--juju-controller` | Target a specific controller | `--controller` |
| `--juju-cloud` | Target a specific cloud | `--cloud` |
| `--juju-switch` | Switch the CLI to the test model, useful while observing `juju status` | — |

## Usage notes

- `--no-juju-setup` skips **tests** marked `juju_setup`. It does not skip fixtures, so
  a module-scoped `deploy` fixture still runs. This is why deploy fixtures do not need
  converting, unless model reuse has to skip them (see `skip_if_deployed` below).
- `--no-juju-teardown` retains models with or without `juju_teardown` markers. The
  marker additionally skips destructive tests.
- `--juju-model=testing` with module `test_charm` is model `testing-test-charm`.
  Update debug commands that hardcode the old model or namespace.
- `--juju-dump-logs` runs whenever it is passed, not only on failure. A path
  after it is the directory (`--juju-dump-logs -s` or `--juju-dump-logs=.logs`).
  See [diagnostics.md](./diagnostics.md).
- Only add `--juju-dump-logs` to a committed command on a branch where
  `pytest-jubilant` is installed. On a pytest-operator branch it is an unrecognized
  argument and fails every job before any test runs.

## `skip_if_deployed`

pytest-operator's `skip_if_deployed` is not a pytest-jubilant marker. Registering it
and leaving it inert does not skip setup on a retained model.

| Old marker sits on | What to do |
|---|---|
| A **test** (often `test_build_and_deploy`) | Keep it a test. Replace the marker with `@pytest.mark.juju_setup`. Do not turn the test into a fixture; that drops a test name. |
| A **fixture** | Ask whether re-running against a retained model is required. If it is not, delete the marker and keep the fixture. If it is, the fixture cannot be skipped by `--no-juju-setup`; move that deploy into a `juju_setup` test and report the new test name. |

Destructive tests that should not run when the model is kept become
`@pytest.mark.juju_teardown`. `--no-juju-teardown` skips those tests and also retains
models. `--keep-models` alone maps to `--no-juju-teardown`; reuse that also skips
setup is `--no-juju-setup --no-juju-teardown --juju-model=<prefix>`.

## Fixtures

| Fixture | Scope | Purpose |
|---|---|---|
| `juju` | module | One temporary model per test module |
| `juju_factory` | module | Additional models: `juju_factory.get_juju(suffix, controller=...)` |

Configure the provided `juju` object (for example `juju.wait_timeout`) rather than
replacing the fixture.
