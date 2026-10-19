# abort_on_fail compatibility

**Type: default.** Applies only if the suite uses the marker.

`abort_on_fail` is a pytest-operator marker. pytest-jubilant has no equivalent.
Implement it locally only if the suite uses it, and keep it minimal.

Semantics to reproduce:

```text
a test marked abort_on_fail fails
        ↓
the module becomes aborted
        ↓
subsequent tests in that module are xfailed
```

pytest-operator's `OpsTest` fixture was module-scoped, so abort state applied to the
whole module. Do not implement class-only state unless the original suite had it.
Support `@pytest.mark.abort_on_fail(abort_on_xfail=True)` only if the repo uses that
form; otherwise omit the argument. Reproduce the behavior the suite relies on, not
every internal of pytest-operator's implementation.

Do not copy `pytest_operator/plugin.py`. Most of that file is model lifecycle, which
this migration must not reintroduce.

Put the shim in a conftest that integration tests collect. Sharing that conftest
with unit tests is fine: the shim does not import Jubilant.

```python
_ABORTED_MODULES: set[str] = set()


def _item_module_name(item: pytest.Item) -> str | None:
    module = getattr(item, "module", None)
    return getattr(module, "__name__", None)


def pytest_configure(config: pytest.Config):
    config.addinivalue_line(
        "markers",
        "abort_on_fail: xfail remaining tests in the module if a marked test fails",
    )


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item: pytest.Item, call: pytest.CallInfo):
    outcome = yield
    assert outcome is not None
    report = outcome.get_result()
    module_name = _item_module_name(item)
    if report.failed and item.get_closest_marker("abort_on_fail") and module_name:
        _ABORTED_MODULES.add(module_name)


def pytest_runtest_setup(item: pytest.Item):
    module_name = _item_module_name(item)
    if module_name and module_name in _ABORTED_MODULES:
        pytest.xfail("previous abort_on_fail test failed")
```

Constraints:

- no model creation or destruction
- no dependency on `OpsTest`
- no lifecycle option registration
- use `getattr(item, "module", None)` where the type checker rejects pytest `Item`
  attributes
- assert or cast `outcome` before `get_result()`
- do not add a docstring `Yields` section for the hookwrapper's `yield`
- key aborted state by module name, a `set[str]`
- the xfail reason is `"previous abort_on_fail test failed"`, not `"aborted"`
