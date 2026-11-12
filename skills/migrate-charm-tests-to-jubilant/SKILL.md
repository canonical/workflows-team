---
name: migrate-charm-tests-to-jubilant
description: 'Migrate charm integration tests from pytest-operator, OpsTest, and python-libjuju to Jubilant and pytest-jubilant. Use when converting keep-models, abort_on_fail, OpsTest, wait_for_idle, build_charm, or async pytest-operator tests.'
---

# Migrate pytest-operator integration tests to Jubilant

Migrate charm integration tests from `pytest-operator` / `OpsTest` / `python-libjuju`
to `jubilant` + `pytest-jubilant`.

```text
pytest-operator  →  Jubilant + pytest-jubilant
not
pytest-operator  →  hand-written pytest-operator using Jubilant
```

Jubilant performs Juju operations. pytest-jubilant owns the pytest/Juju model
lifecycle. Keep only repository-specific pytest behavior the plugin does not provide.

## How to read this skill

- **Rule** — holds for every repository. Do not deviate without telling the user.
- **Default** — what to do unless the repository or user says otherwise.
- **Observation** — seen in some repositories. Check whether it applies; do not apply
  it blindly.

The repository and branch being migrated are the source of truth for topology,
channels, bases, resources, relations, actions, tooling, and expected behavior. Never
copy these from another repository, charm, or track, and never from this document's
examples.

## Do not invent

If the repository or the installed library does not say it, confirm it from those
sources or ask the user. Do not fill the gap from this skill. Snippets, default
numbers, and version notes here are illustrations of one release pair. They are
not a source.

Use sources in this order:

1. **The repository.** Topology, channels, resources, markers, and whether an
   argument was passed at all. An omitted `idle_period`, `timeout`,
   `raise_on_error`, or `raise_on_blocked` keeps the default of the python-libjuju
   version the repo pins. Read that default from the installed package or its
   source. Do not copy a number written in this skill when the pin differs.
2. **The installed packages.** Jubilant and pytest-jubilant signatures, plugin
   flags, and whether `all_active` includes agent idle. If a snippet here
   disagrees with `inspect.signature` or the plugin `--help`, the installed
   package wins. If those packages are not installed and the docs do not settle
   it, stop.
3. **The user.** Ask when two readings are both plausible. State the default you
   will use if they decline. Do not pick one and mention it only in the final
   report. Ask about: the CI runner and what it can run; which layer packs the
   charm and how the path reaches tests; a resource that could come from metadata
   `upstream-source` or a CLI flag; a deploy that could be a bundle or a list of
   apps; model reuse when `skip_if_deployed` is on a fixture; an omitted wait
   default you could not read; a signature or flag you could not inspect;
   dependency policy and lock tool; whether partial migration is acceptable.

`juju.cli(...)` is not a way through a gap. Use it only after a lookup shows
there is no typed method. If you cannot look it up, stop and ask. Do not invent
the invocation.

## Rules

1. Migration is integration-test-only. Do not change charm source, unit tests,
   scenario or `ops.testing`, interface tests, terraform, or spread.
2. Use pytest-jubilant's `juju` fixture. Do not write a model fixture, manage models
   manually, or register lifecycle options the plugin already provides.
3. Preserve topology, configuration, and wait semantics exactly. Never weaken an
   assertion, widen a wait, or delete a check to make the suite pass.
4. The charm under test is the locally built one. Never add a Charmhub fallback for it.
   Other applications, including every Charmhub application a bundle already
   deploys, stay on the channel and revision the tests already used.
5. Preserve failure diagnostics and `abort_on_fail` behavior if the suite had them.
6. Never invent. Follow "Do not invent": the repo, then the installed packages,
   then the user. A snippet in this skill does not override those.
7. Do not lose tests. Compare test names before and after.
8. Report environment failures separately from migration failures.
9. If the integration suite already uses the plugin `juju` fixture and has no
   `OpsTest` / `pytest-operator` / `build_charm`, stop. Do not rewrite it.

## Defaults

| Topic | Default |
|---|---|
| Deploy / stack fixtures | Keep them. Do not convert into `juju_setup` tests unless `skip_if_deployed` is on the fixture and the user wants model reuse. |
| `juju_setup` / `juju_teardown` | A `skip_if_deployed` **test** becomes `juju_setup`. A `skip_if_deployed` **fixture** stays a fixture unless the user wants model-reuse, in which case that deploy becomes a `juju_setup` test. See [plugin-flags.md](./references/plugin-flags.md#skip_if_deployed). |
| `--keep-models` | Do not register it. Use the plugin's retention flag. |
| `--charm-file` or equivalent | Keep if the repo already has it. |
| Wait timeout | Pass explicit `timeout=`, or set `juju.wait_timeout`. Do not wrap `juju`. |
| `abort_on_fail` | If the suite uses the marker, a local shim is required; the marker is otherwise inert. |
| Failure diagnostics | Wire the plugin's log dumping into the committed test command; retain in CI. |

## Discover before assuming

Detect these from the repository. Do not assume the examples in this skill (tox,
GitHub Actions, Poetry, Kubernetes) match.

| Detect | Where to look |
|---|---|
| Task runner / entry point | `tox.ini`, `justfile`, `Makefile`, `noxfile.py`, scripts |
| CI system and its pre-test setup | workflow files; whatever the repo uses |
| Dependency tool and groups | `pyproject.toml`, lock file, `requirements*` |
| Substrate | K8s, machine/LXD, or multi-cloud, from the charm and CI |
| How the charm path reaches tests | existing option, env var, or glob |
| Charm layout | single charm, multiple bases/arches, monorepo, sidecar charms |

When the repository's tooling is not one of these examples, apply the same
principle with that tooling and tell the user what you did. Scenario, unit,
terraform, and spread entry points are out of scope even when they sit next to
the integration job.

## Flow

1. **Inventory and confirm unknowns** — know what exists; ask what you cannot infer.
2. **Dependencies** — current compatible versions, one lock.
3. **Lifecycle and packing** — plugin fixture; charm path supplied from outside pytest.
4. **Convert and preserve behavior** — same topology, semantics, diagnostics.
5. **Validate and clean up** — real commands, no lost tests, no leftovers.

---

# 1. Inventory and baseline

Before editing, write the baseline the step 6 diff reads. Use the old environment while `pytest-operator` is still installed. If collection fails, enumerate `def test_` from source into the same file. Record topology from this branch. Stop when the suite is already on the plugin fixture. [validation-and-cleanup.md](./references/validation-and-cleanup.md), [known-environment-issues.md](./references/known-environment-issues.md), [api-mappings.md](./references/api-mappings.md#third-party-test-helpers).

```bash
pytest --collect-only -q tests/integration > /tmp/collected-before.txt
```

# 2. Dependencies

Read the pytest floor from the installed pytest-jubilant metadata. Raise it only in environments that install pytest-jubilant, and in other groups only when they resolve into the same lock. Use the repository's existing lock tool. [known-environment-issues.md](./references/known-environment-issues.md#pytest-version-floor).

# 3. Lifecycle and packing

Use the plugin `juju` fixture. Set `juju.wait_timeout` from the pinned default when a wait omitted `timeout`. Pack outside pytest. [plugin-flags.md](./references/plugin-flags.md), [packing.md](./references/packing.md), [api-mappings.md](./references/api-mappings.md#wait_for_idle-argument-mapping).

# 4. Convert the tests

`async def` that only awaited python-libjuju becomes `def`. Preserve deploy arguments and module order. Look up anything unmapped; do not invent it. [api-mappings.md](./references/api-mappings.md), [worked-example.md](./references/worked-example.md).

# 5. Preserve repo-specific pytest behavior

Add the `abort_on_fail` shim and the log-dumping flag (only on a branch where the plugin is installed). Translate invocation flags. A root `conftest.py` shared with unit tests must not import Jubilant; drop `asyncio_mode` when no async tests remain; do not declare either plugin; register markers still in use. [abort-on-fail.md](./references/abort-on-fail.md), [diagnostics.md](./references/diagnostics.md), [plugin-flags.md](./references/plugin-flags.md).

# 6. Validate and clean up

Collection diff, lint, and unit tests through the repository's commands. Run integration only when the CI-equivalent cloud is available; otherwise report the blocker and do not weaken a wait. [validation-and-cleanup.md](./references/validation-and-cleanup.md), [environment-prerequisites.md](./references/environment-prerequisites.md).

```bash
pytest --collect-only -q tests/integration > /tmp/collected-after.txt
names() { grep -oE '(::|(async )?def )test_[A-Za-z0-9_]+' "$1" | grep -oE 'test_[A-Za-z0-9_]+' | sort -u; }
diff <(names /tmp/collected-before.txt) <(names /tmp/collected-after.txt)
```

---

# Completion checklist

- collection diff empty or explained, using the `names` command above
- lint and unit tests passed through the repository's own commands
- integration passed, or the environment blocker is reported and no wait was weakened
- no charm source, unit, scenario, terraform, or spread edits

The final report lists: defaults applied where the user did not specify, environment
failures separated from migration failures, behavior that could not be preserved
exactly, and test renames.

## References

Confirm every API against these; they are authoritative, other migrations are not.

- Ops migration guide: https://canonical.com/juju/docs/ops/latest/howto/migrate/migrate-integration-tests-from-pytest-operator/
- Jubilant API: https://canonical.com/juju/docs/jubilant/reference/jubilant/
- pytest-jubilant: https://github.com/canonical/pytest-jubilant
- Plugin source: https://github.com/canonical/pytest-jubilant/blob/main/pytest_jubilant/_main.py
- pytest-operator (legacy behavior only): https://github.com/charmed-kubernetes/pytest-operator

Local references:

- [api-mappings.md](./references/api-mappings.md) — call-by-call conversions
- [worked-example.md](./references/worked-example.md) — before/after, K8s and machine
- [packing.md](./references/packing.md) — charm path, layouts, packing layer
- [plugin-flags.md](./references/plugin-flags.md) — pytest-jubilant options
- [abort-on-fail.md](./references/abort-on-fail.md) — marker shim
- [diagnostics.md](./references/diagnostics.md) — log dumping and CI retention
- [environment-prerequisites.md](./references/environment-prerequisites.md) — cloud checks
- [validation-and-cleanup.md](./references/validation-and-cleanup.md) — final checks
- [known-environment-issues.md](./references/known-environment-issues.md) — observed failures
