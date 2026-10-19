# Validation and cleanup

**Type: checklist.**

## Validate

Local definition of done, through the repository's own commands:

1. Pack, when the repository has a charm under test.
2. Collection name diff for the integration tests (command in SKILL.md).
3. Lint.
4. Unit tests.

Integration tests run only when the CI-equivalent cloud is actually available:
controller, substrate, and the pre-test steps the workflow performs. A laptop
without that cloud is an environment blocker, not a failed migration. Do not
weaken a wait or delete a check to get past it. Report the blocker and stop.
Say explicitly that collection, lint, and unit passed and integration was not run.

When the cloud is available, run one migrated file at a time through the
repository's real command, not a bare `pytest`, then the rest of the integration
suite the same way.

A shrinking suite is the most common silent migration failure. Compare test **names**
before and after (see SKILL.md) and explain every difference.

While debugging, retention and log-dumping flags are more useful than print statements.

## Clean up

Remove: `OpsTest` / `ops_test`, custom model fixtures, local `--keep-models`,
`build_charm`, `track_model`, and the dependencies removed in the dependency step.

Remove migration-transition wording from permanent docstrings and comments, such as
"`idle_period` equivalent". Describe what the code does, not what it replaced.

Keep: the charm-path option, `abort_on_fail` compatibility, diagnostics, and fixtures
supplying repository-specific resources (charm paths, resources, app names,
credentials, relation data, sidecar charms). Such fixtures may consume the plugin
`juju` object; they must not replace it.

```bash
grep -RniE 'ops_test|OpsTest|pytest_operator|pytest-operator|\bbuild_charm\b|\btrack_model\b|--keep-models|\bfrom juju\b|\bimport juju\b' tests
grep -Ei 'pytest-operator|python-libjuju' <lock file>
```

`\bfrom juju\b` and `\bimport juju\b` do not match `jubilant`. A hit on
`import jubilant` means the pattern was left unanchored; fix the pattern, do not
edit the import.

A lock entry named `juju` stays when a library the tests still import depends
on it. Do not widen this grep to that package name.

Every remaining match must be understood.

Lock-file changes do not remove packages from an existing virtual environment. Recreate
test environments and confirm `pytest-operator` is absent from a fresh one. **Only
delete environment directories inside the repository being migrated**; verify the
working directory first.

Review `git status` and `git diff --stat`. Expected changes: `tests/`, dependency
manifests, the lock file, task-runner and tox/nox configuration, CI workflows and their
setup scripts. Anything else needs justification.

## Already migrated, or partially migrated

If the integration suite already takes pytest-jubilant's `juju` fixture and the
leftovers grep shows no `OpsTest`, `pytest-operator`, or `build_charm`, stop. Do not
rewrite helpers or docstrings that already match this skill.

A repo may contain both. Migrate the pytest-operator files only. Do not treat an
existing Jubilant file as a style template for lifecycle: a hand-rolled `temp_model`
fixture predating pytest-jubilant is still deleted, and the dependent file updated
to the plugin fixture. Use existing Jubilant files as authority on topology, never
on lifecycle design.
