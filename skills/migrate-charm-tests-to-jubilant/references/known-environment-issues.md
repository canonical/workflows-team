# Known environment and toolchain issues

**Type: observations, not rules.** These were seen in specific repositories and
setups, and may not apply to yours. Consult when a failure occurs outside the test
code, try the fixes in order, and report to the user which one was needed. None are
migration defects.

## Snap confinement blocks the Juju CLI

When a task runner invokes the test stack through a snap-installed tool, the `juju`
snap may refuse to run inside another snap's cgroup:

```text
... is not a snap cgroup for tag snap.juju.juju
```

Packing succeeds, then every model operation fails.

Under tox, the cause can also be environment isolation: tox drops the host session
variables the snap needs. Pass them through in `tox.ini`:

```ini
[testenv:integration]
passenv =
    HOME
    XDG_*
    DBUS_*
    SNAP*
```

If the narrow list does not fix it, fall back to `passenv = *`. It is broader than
necessary, so prefer the narrow list when it works. Report which one was needed.

If the runner itself is a snap, install it outside snap confinement or invoke pytest
directly from the created virtual environment.

## Pinned formatters break on newer interpreters

The first failure after raising the interpreter is often a linter, not pytest — e.g.
an old formatter raising `AttributeError` on a removed `ast` node. Check
`requires-python` and select a compatible interpreter before assuming the tests are
at fault.

## Task runners swallow tox flags

Per-invocation overrides only work when invoking tox directly. If the entry point is
a `justfile`/`Makefile` wrapping tox without passthrough, pin the interpreter in
`tox.ini` so every entry point agrees.

## Linter drift flags untouched source

Unpinned lint extras pull newer analyzers that flag pre-existing code the migration
never touched. Suppress the new check in lint configuration; do not edit charm source
to satisfy it. Tell the user.

New virtual-environment directories may also need adding to linter skip lists.

## Strict typing on pytest hookwrappers

Under strict type checking, the value yielded by a hookwrapper is `None`-typed.
Assert or cast before calling `get_result()`. Do not add a docstring `Yields` section
purely because a hookwrapper yields.

## Test imports fail with `No module named 'tests'`

Bare `pytest --collect-only` can fail when tests import shared modules such as
`tests/integration/helpers.py`. Set the import path in configuration rather than
exporting `PYTHONPATH`:

```toml
[tool.pytest.ini_options]
pythonpath = [".", "src", "lib"]
```

Adjust the entries to the directories the repository actually imports from.

## pytest version floor

Read the floor from the installed `pytest-jubilant` metadata. Which groups to
raise is in SKILL.md. When last read, pytest-jubilant 2.x required
`pytest>=9.1.1`. If the installed metadata differs, it wins. If you cannot read
it, ask. Do not copy the version from this note.

## Stale artifacts and environments

- A leftover packed charm in the repository satisfies a "single artifact" glob. Clean
  before packing.
- Lock updates do not prune existing environments; recreate them.
- Confirm working directory and branch before interpreting a failure. A stale
  environment in another repository yields confusing import errors such as
  `ModuleNotFoundError: No module named 'pytest_asyncio'`.

## Missing cluster or cloud prerequisites

Suites frequently require components CI installs in a separate step — ingress
controllers, load-balancer pools, storage classes, LXD profiles, images for a
required base. Absence looks like a test bug (empty addresses, unschedulable units)
but is not. Read the CI workflow for pre-test setup and reproduce it.
