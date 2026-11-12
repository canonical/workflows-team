# Worked example

**Type: example.** Names, channels, and topology are placeholders. Take them from
the repository. Wait arguments, including any omitted default, come from
[api-mappings.md](./api-mappings.md). Do not copy a count out of that file.

## Kubernetes charm

Before:

```python
@pytest_asyncio.fixture(scope="module")
async def deploy(ops_test: OpsTest):
    charm = await ops_test.build_charm(".")
    await ops_test.model.deploy(charm, application_name=APP, resources=RESOURCES)
    await ops_test.model.deploy(DEP_APP, channel=DEP_CHANNEL, trust=True)
    await ops_test.model.integrate(f"{APP}:db", f"{DEP_APP}:database")

    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=[APP, DEP_APP],
            status="active",
            raise_on_blocked=False,
            idle_period=30,
            timeout=600,
        )
    assert ops_test.model.applications[APP].units[0].workload_status == "active"


@pytest.mark.abort_on_fail
async def test_action(ops_test: OpsTest):
    action = await ops_test.model.applications[APP].units[0].run_action("restart")
    await action.wait()
    assert action.results["result"] == "ok"
```

After:

```python
# fast_forward has no Jubilant equivalent: keep it as a local helper
# (implementation in api-mappings.md).
from helpers import fast_forward


@pytest.fixture(scope="module")
def deploy(juju: jubilant.Juju, charm_path: pathlib.Path, charm_resources: dict[str, str]):
    juju.deploy(charm_path, app=APP, resources=charm_resources)
    juju.deploy(DEP_APP, channel=DEP_CHANNEL, trust=True)
    juju.integrate(f"{APP}:db", f"{DEP_APP}:database")

    with fast_forward(juju):
        # ready, error, delay, and successes: api-mappings.md, from this wait_for_idle.
        juju.wait(..., timeout=600)
    assert juju.status().apps[APP].units[f"{APP}/0"].is_active


# The marker only works if the repo has the abort_on_fail shim.
@pytest.mark.abort_on_fail
def test_action(juju: jubilant.Juju):
    # juju.run raises TaskError if the action fails; no explicit success check needed.
    task = juju.run(f"{APP}/0", "restart")
    assert task.results["result"] == "ok"
```

## Machine charm variant

Differences that matter on a machine substrate:

- no OCI `resources=`; deploy the packed charm with an explicit `base=` only if the
  original pinned a series
- constraints and placement are often significant, so preserve them
- `juju.ssh(unit, cmd)` replaces `ops_test.juju("ssh", ...)`; there is no `container=`
- there is no Kubernetes namespace, so the bare-model-name note in api-mappings.md
  usually does not apply

```python
@pytest.fixture(scope="module")
def deploy(juju: jubilant.Juju, charm_path: pathlib.Path):
    juju.deploy(charm_path, app=APP, base=BASE, constraints={"mem": "4G"}, num_units=UNITS)
    juju.wait(..., timeout=900)  # omitted idle_period: api-mappings.md, from the pin
```

`BASE`, `constraints`, and `UNITS` come from the original test. If the original passed
none of them, pass none.

`units[0]` in the old test is `units[f"{APP}/0"]` in the new one. Action results
and wait arguments are in [api-mappings.md](./api-mappings.md).
