# Jubilant API mappings

**Type: reference.** Placeholder names. The skill's "Do not invent" rule wins.
Confirm each signature against the installed package before using it.

Primary sources:

- https://canonical.com/juju/docs/ops/latest/howto/migrate/migrate-integration-tests-from-pytest-operator/
- https://canonical.com/juju/docs/jubilant/reference/jubilant/

For pytest-jubilant command-line options and fixtures, see
[plugin-flags.md](./plugin-flags.md).

Version notes below were read from Jubilant 1.14.0 and python-libjuju 3.5.2.1.
If the repository's pins differ, their source wins. If you cannot read them, ask.

## Core mappings

| pytest-operator / python-libjuju | Jubilant |
|---|---|
| `ops_test.model.deploy(...)` | `juju.deploy(...)` |
| `model.deploy(bundle)` / `juju deploy ./bundle.yaml` | `juju.deploy(bundle_path, overlays=..., trust=...)` — see Bundles |
| `model.add_relation(...)` / `model.integrate(...)` | `juju.integrate(...)` |
| relation removal | `juju.remove_relation(...)` |
| `application.set_config(...)` | `juju.config(...)` |
| `model.wait_for_idle(...)` | `juju.wait(...)` — see Status and waits |
| `model.block_until(predicate)` | `juju.wait(...)` with that condition as `ready` |
| `unit.run(...)` | `juju.exec(...)` |
| `unit.run_action(...)` + `.wait()` | `juju.run(...)` → `Task` |
| `application.refresh(...)` / `juju refresh` | `juju.refresh(app, path=..., resources=..., revision=...)` |
| python-libjuju status objects | `juju.status()` — `units` is a dict, see below |
| `application.destroy()` | `juju.remove_application(...)`, then wait (see below) |
| `ops_test.model.name` | `juju.model`, stripped of any controller prefix (see below) |
| `unit.relation_data` / `app.relations` | `show_unit` to find the relation; `juju.exec` + `relation-get` for the unit databag (see below) |
| `application.scale(scale=N)` | `juju.cli("scale-application", app, str(N))` |
| `application.add_unit(count=N)` | `juju.add_unit(app, num_units=N)` |
| `model.add_secret(...)` | `juju.add_secret(name, content)` → `SecretURI` — see Secrets |
| `model.grant_secret(...)` | `juju.grant_secret(identifier, app)` |
| `model.create_offer(...)` / `juju offer` | `juju.offer(app, endpoint=...)` — see Offers |
| `model.consume(...)` / `juju consume` | `juju.consume(model_and_app, alias, controller=...)` |
| `ops_test.juju(...)` | `juju.cli(...)` |
| `ops_test.juju("ssh", "--container", C, U, cmd)` | `juju.ssh(U, cmd, container=C)` |
| `ops_test.juju("scp", ...)` | `juju.scp(...)` — verify signature |
| `ops_test.run(...)` (non-Juju command) | `subprocess.run(...)` |
| `ops_test.track_model(...)` | `juju_factory.get_juju(suffix, controller=...)` — see Cross-model |
| `ops_test.build_charm(...)` | pack outside Python tests |
| `ops_test.fast_forward()` | local context manager (below) |

If there is no dedicated Jubilant method, use `juju.cli(...)`. It runs the Juju CLI
against the fixture model and raises `CLIError` on failure.

Old python-libjuju code may use `series="jammy"`. Current Jubilant APIs use a Juju
base such as `base="ubuntu@22.04"`. Where the original passed no series, do not invent
a base. Do not copy channels or bases from another track.

## Status and waits

Use `status = juju.status()` instead of python-libjuju live Application/Unit objects.

`status.apps[app].units` is a **dict** keyed by unit name (`"app/0"`), not a list.
`units[0]` does not select the first unit. Workload status and its message live on
`workload_status`; `is_active` is that workload status only and says nothing about
the unit agent.

```python
status.apps[app]
unit = status.apps[app].units[f"{app}/0"]
unit.address
unit.is_active                       # workload_status.current == "active"
unit.workload_status.message         # status message the old unit object exposed
unit.leader                          # replaces get_leader_unit(...)
unit.juju_status.current             # agent status, e.g. "idle" or "executing"
```

Leader, when the old test called `get_leader_unit`:

```python
leader = next(name for name, unit in status.apps[app].units.items() if unit.leader)
```

If the old test polled until a workload status message appeared, keep that condition
inside `ready`. Jubilant has no helper for it; do not drop the check.

Prefer `juju.wait` over polling loops. `model.block_until(predicate)` is also
`juju.wait`: put the predicate in `ready`, and keep its timeout.

Do not weaken old `wait_for_idle` conditions. Preserve applications,
active/blocked/error expectations, timeout, error handling, and stability
requirements.

### wait_for_idle argument mapping

When the old call omitted an argument, preserve that argument's default from the
pinned python-libjuju. Read the signature. These cells are python-libjuju 3.5.2.1
and Jubilant 1.14.0. If the pin differs, or you cannot read it, do not copy them.

| Argument | Default on python-libjuju 3.5.2.1 |
|---|---|
| `timeout` | `10 * 60` seconds. Jubilant 1.14 `wait_timeout` is 3 minutes; set `juju.wait_timeout` to this instead |
| `idle_period` | `15` seconds of continuous agent idle |
| `raise_on_error` | `True` |
| `raise_on_blocked` | `False` |

| `wait_for_idle` argument | Jubilant |
|---|---|
| `status="active"` (or another status) | the matching `all_*` for those apps. On Jubilant 1.14 `all_active` is workload status only, so also `all_agents_idle` for the same apps unless the installed helper already checks agents |
| `idle_period` | seconds, held with `(successes - 1) * delay`. Jubilant 1.14 sleeps after each check, `delay` defaults to 1, `successes` defaults to 3. Do not set `successes` to the idle seconds |
| `timeout` passed | `timeout=` |
| `timeout` omitted | `juju.wait_timeout` set to the libjuju default above |
| `raise_on_error` true, including when that is the omitted default | `error=` includes `any_error`, scoped to the same apps |
| `raise_on_error` false | no `any_error` |
| `raise_on_blocked` true | `error=` includes `any_blocked`, scoped to the same apps |
| `raise_on_blocked` false, including when that is the omitted default | no `any_blocked` |
| `wait_for_exact_units=N` | `len(status.apps[app].units) == N` inside `ready` |

```python
# IDLE_SECONDS: the passed idle_period, or the omitted default from the table.
# DELAY: Juju.wait's delay on the installed Jubilant.
juju.wait(
    ready,  # all_* for the waited apps, plus all_agents_idle when required above
    error=...,  # scoped; omit the checks the table says to omit
    delay=DELAY,
    successes=int(IDLE_SECONDS / DELAY) + 1,
    timeout=...,  # the passed timeout, or rely on wait_timeout when it was omitted
)
```

Unscoped, `any_error` or `any_blocked` aborts when any application in the model
goes blocked or errors, including a dependency that is legitimately blocked
mid-deploy:

```python
error=jubilant.any_blocked                                   # wrong: whole model
error=lambda status: jubilant.any_blocked(status, APP)       # right: app under test
```

When one `error=` callable must cover both error and blocked, combine the scoped
checks in that lambda. Do not pass two `error=` arguments.

## Actions

```python
task = juju.run("app/0", "action-name", params)
```

`task.results` contains charm-defined result keys only. It does **not** contain Juju's
`return-code`, `stdout`, or `stderr`.

Use `task.return_code`, `task.stdout`, `task.stderr`, and `task.status`.

Do not convert `assert result.results == {"return-code": 0}` mechanically. Use:

```python
assert task.status == "completed"
assert task.return_code == 0
```

Failed actions may raise `jubilant.TaskError`. `juju.run()` already checks action
failure. When testing expected failure, catch `TaskError` and inspect `exc.task`.

Refresh and upgrade keep the old charm path, resources, revision, and channel.
`juju.refresh` has those as keyword arguments; do not drop `resources` because the
old call passed them positionally to `juju refresh`.

## Command execution

```python
task = juju.exec(..., unit="app/0")
```

`exec` returns a `Task` and checks errors. Do not check
`task.results["return-code"]`.

For commands that are not Juju operations — `kubectl`, `lxc`, shell tooling — use
`subprocess.run` directly rather than routing through Jubilant.

## Secrets

`juju.add_secret` takes a **dict** of key to value and returns a `SecretURI`
(a `str` subclass). python-libjuju often took a list of `"key=value"` strings;
convert that list to a dict. Do not fold the secret into application config and
drop the grant.

```python
uri = juju.add_secret("secret-name", {"token": token})
juju.grant_secret(uri, APP)          # name or URI; grant every app the old call granted
```

If the old test stored the return value and passed it as config, keep passing
`uri`. If it granted by secret name, `juju.grant_secret("secret-name", APP)`
matches. Grant and add are separate calls; keep both.

## Bundles

`juju.deploy` deploys a bundle when `charm` is a bundle path (it must start with
`/` or `.`). Overlays are the `overlays=` iterable, applied in order. `trust=True`
is `--trust` and applies only when the old deploy passed it.

```python
juju.deploy(
    bundle_path,
    overlays=[overlay_path],
    trust=True,
)
```

Do not rewrite a bundle into per-application `juju.deploy` calls. That drops
overlay order, bundle-level constraints, and the channels written in the bundle.

- Applications the bundle installs from Charmhub stay on the channel and revision
  in the bundle. Do not rebuild them locally.
- The charm under test, when the bundle points at a local path, must be the
  packed artifact. Do not point that path at Charmhub.
- A repository that contains only a bundle has nothing to pack. Deploy the bundle
  as written.
- Do not pass `num_units`, `base`, or `resources` on a bundle deploy unless the
  old command passed the same flag. `num_units` defaults to 1 and is omitted from
  the CLI unless it differs, so leaving it off is the safe choice.

Names, overlay paths, and `trust` come from the test being migrated.

## Offers and cross-model controllers

`juju.offer` and `juju.consume` are typed methods. Do not reimplement them with
`juju.cli` when the installed Jubilant has them.

```python
juju.offer(APP, endpoint="endpoint-name")
juju.consume(f"{other_model}.{APP}", "local-alias", controller=other_controller)
juju.integrate(f"{consumer}:endpoint-name", "local-alias")
```

`consume`'s first argument is `model.application`, not `controller:model.application`.
The plugin stores `juju.model` as `controller:model` when a controller is in use.
Strip the prefix before interpolating it:

```python
bare_model = juju.model.rpartition(":")[2]
```

A second model is `juju_factory.get_juju(suffix, controller=...)`. `controller`
selects which bootstrapped controller owns that model. Pass it when the old test
used two controllers (Kubernetes and LXD, for example). Do not deploy a machine
charm into the Kubernetes model because the worked example only shows one `juju`.

```python
def controller_by_cloud(*clouds: str) -> str:
    """Return a bootstrapped controller whose cloud is one of ``clouds``.

    ``include_model=False`` keeps the plugin from injecting the fixture model
    into ``juju controllers``.
    """
    output = jubilant.Juju().cli("controllers", "--format", "json", include_model=False)
    controllers = json.loads(output)["controllers"]
    for name, info in controllers.items():
        if info.get("cloud") in clouds:
            return name
    raise RuntimeError(f"no controller for clouds {clouds}")


k8s = juju_factory.get_juju("k8s", controller=k8s_controller)
machine = juju_factory.get_juju("machine", controller=machine_controller)
```

If the original named a controller, keep that name. Discover a controller only
when the original discovered one, or when CI creates controllers whose names are
not stable. Which cloud is Kubernetes and which is a machine substrate comes from
the test and its CI setup, not from this example. Do not copy application names,
endpoints, or channels from another repository.

Set `wait_timeout` on each model object the test waits on. One assignment on the
module's default `juju` does not cover a factory model.

## fast_forward

There is no Jubilant equivalent. If an existing test genuinely depends on accelerated
`update-status`, write a local context manager. Preserve the interval the call site
passed; the default `"10s"` applies only when the old call used the default.

```python
@contextlib.contextmanager
def fast_forward(juju: jubilant.Juju, interval: str = "10s"):
    previous = (juju.model_config() or {}).get("update-status-hook-interval", "5m")
    juju.model_config({"update-status-hook-interval": interval})
    try:
        yield
    finally:
        juju.model_config({"update-status-hook-interval": previous})
```

Restore only the value this helper changed. If the original set
`update-status-hook-interval` outside `fast_forward` and left it for the rest of
the module, keep that assignment. Do not wrap it in this helper; restoring
afterwards changes every later test.

## Application removal

Omitting `--no-wait` is not a wait: the CLI returns while `life` is `dying`.
`block_until_done=True` polls until the name is absent, and returns on the
first true check (`successes=1`). `timeout=None` has no deadline; Jubilant
requires one, so use the pinned `wait_for_idle` timeout and report that ceiling.

```python
juju.remove_application(app)
juju.wait(lambda status: app not in status.apps, successes=1, timeout=...)
```

## Relation data

`show_unit` finds the relation (`relation_id`, endpoints). It has no
provider/requirer role, and `local_unit.data` can be `None` while `relation-get`
already has the keys. Read the unit bag the way the old test did:

```python
info = juju.show_unit(f"{app}/0")
rel = next((r for r in info.relation_info if r.endpoint == "endpoint-name"), None)
assert rel is not None, "relation not found"
task = juju.exec(
    f"relation-get --format=yaml -r {rel.relation_id} - {unit}",
    unit=unit,
)
assert task.return_code == 0, task.stderr
data = yaml.safe_load(task.stdout) or {}
```

`relation.provides` is the other application when this charm's endpoint is
under `requires`, and this application when it is under `provides`. Stop if
`metadata.yaml` does not say. `local_unit` and `related_units` are different bags.

## Model name for Kubernetes namespaces

`juju.model` is the string the `Juju` object was created with. The plugin prefixes it
with the controller (`<controller>:<model>`) when a controller is in use, so it is
not always the bare name `ops_test.model.name` returned. The Kubernetes namespace is
the bare name:

```python
assert juju.model
namespace = juju.model.split(":")[-1]
```

Use this wherever the old code passed `ops_test.model.name` to Lightkube, `kubectl`,
or any other non-Juju API. `split(":")[-1]` and `rpartition(":")[2]` agree when
there is one colon.

## Third-party test helpers

Helpers from other charm libraries (for example `charmed_kubeflow_chisme.testing`,
`cosl`, `data_platform_libs`) often take an async python-libjuju `Model` or
`Application`. They cannot be called with a `jubilant.Juju`. When a test imports one:

1. check whether the installed version has a Jubilant-compatible variant
2. otherwise re-implement the needed behavior locally in `tests/integration/helpers.py`
   with `juju.deploy`, `juju.integrate` and `juju.wait`
3. preserve the original wait conditions (applications, status, timeout)
4. tell the user which helpers were re-implemented, so they can switch back when the
   library migrates

## Anything still unmapped

Storage, constraints, bindings, and placement that were arguments to `deploy` stay
keyword arguments of `juju.deploy`. Do not drop them. A call that is not in the
tables above follows "Unmapped patterns" in SKILL.md. Do not reintroduce
python-libjuju because a mapping is unfamiliar.
