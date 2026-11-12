# Charm selection and packing

**Type: rule for the contract, default for the packing layer.**

pytest-jubilant deliberately does not build charms.

```text
pack must happen before pytest needs the charm path
```

Never pack inside a Python fixture.

## Charm-path contract

Replace `await ops_test.build_charm(...)` with an explicit contract: use the
repository's charm-path option if present, otherwise exactly one packed artifact from
the expected directory. Assert the file exists. **Never add a Charmhub fallback for the
charm under test**: a silent fallback turns a build failure into a green run against
the published charm.

```python
@pytest.fixture(scope="session")
def charm_path(request: pytest.FixtureRequest) -> pathlib.Path:
    charm_files = request.config.getoption("--charm-file")
    if charm_files:
        assert len(charm_files) == 1
        charm = pathlib.Path(charm_files[0]).resolve()
    else:
        charms = list(pathlib.Path().glob("*.charm"))
        assert charms, "No packed charm found"
        assert len(charms) == 1, f"Found multiple charms: {charms}"
        charm = charms[0].resolve()

    assert charm.is_file()
    return charm
```

Keep the repo's existing option name. Do not add `--charm-file` if the repo delivers
the path another way (environment variable, fixed directory).

## Layouts the contract must handle

- **Multiple bases or architectures**: packing may emit several artifacts, so "exactly
  one `*.charm`" is wrong. Select by the base/arch under test or require an explicit
  path, deterministically, and assert it.
- **Monorepos with several charm directories**: pack each in its own directory and pass
  unambiguous paths. Do not glob the repository root.
- **Test/sidecar charms**: pack and pass them explicitly, same contract. A
  `build_charm` of a sidecar inside a test moves out of pytest with the main charm.
  Do not leave it as a Python fixture.
- **Stale artifacts**: clean previously packed charms before packing, or the glob
  selects an old build.
- **Bundles**: a `bundle.yaml` (plus overlays) is deployed with `juju.deploy`, not
  unpacked into one `deploy` per application. See [api-mappings.md](./api-mappings.md#bundles).
  If the repository contains no charm, there is nothing to pack.
- **Resources**: keep the source the tests already use. That may be
  `metadata.yaml` `upstream-source`, a required CLI option, or a file CI builds.
  Do not invent `upstream-source` for a required image flag, and do not invent a
  flag for a resource the metadata already names. A required option stays required.

## Which layer packs (default, confirm with the user)

Preserve the repository's existing entry point: a CI step, a dedicated pack
environment, or a pack command preceding pytest. Do not restructure the task runner
without cause.

Observation: in one family of repositories, reviewers preferred packing as an explicit
step in the task runner (`justfile`, `Makefile`) before invoking the test environment,
over adding the pack tool to a tox environment through `allowlist_externals`. Another
repository in the same family kept packing in tox. Follow the user's answer.
