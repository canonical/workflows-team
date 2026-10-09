# Environment prerequisites

**Type: checklist.** Run the checks that match the repository's substrate.

pytest-jubilant manages models. It does not bootstrap controllers or provision
infrastructure. Verify the target cloud is healthy before debugging any test.

Common to all clouds:

```bash
juju controllers
juju models
juju status -m controller
```

Then, by substrate:

- **Kubernetes**: node readiness and API reachability, plus any cluster components the
  suite needs but the cloud does not provide (ingress controllers, load-balancer
  address pools, storage classes, DNS add-ons).
- **Machine / LXD**: LXD initialisation and profiles, storage pools, network bridges,
  available images for the required bases.
- **Multi-cloud or cross-model**: every controller and model the suite touches, plus
  offer reachability.

Read the CI configuration for setup steps that run *before* the test command. Their
absence locally produces failures that look like test bugs but are not.

Report environment failures separately from migration failures. Never change test
semantics to make an infrastructure failure disappear.

Toolchain and confinement failures observed in practice are in
[known-environment-issues.md](./known-environment-issues.md).
