# workflows-team

This repository consolidates common tooling, templates, and automation used across the Canonical workflows team. It supports secure artifact delivery, SBOM generation, CI/CD standardization, and SSDLC-aligned compliance workflows

### Automation

#### SBOM and secscan

SBOM generation and vulnerability scanning with [SBOMber](https://github.com/canonical/sbomber/) and secscan, as required by SEC0025.

```
.github/workflows/sbom_secscan.yaml   # CI workflow
sbom_secscan_manifests/
├── airflow.yaml                      # Charmed Airflow charms and rocks
├── nifi.yaml                         # Charmed NiFi charms and rocks
└── temporal.yaml                     # Charmed Temporal charms and rocks
```

The [CI workflow](.github/workflows/sbom_secscan.yaml) runs one job per manifest in [`sbom_secscan_manifests/`](sbom_secscan_manifests/):

- **Scheduled:** on 15 March and 15 September, for every product.
- **Manual:** from the Actions tab (`workflow_dispatch`); choose `all` or a single product.

Results are sent to the long-term SSDLC scan registry and uploaded as a workflow artifact named after the product.

**Adding an artifact:** add it to its product's manifest. Every artifact must define `type`, `channel`, `base` and `ssdlc_params`:

```yaml
# charm
- name: airflow-scheduler-k8s
  type: charm
  channel: 3.1/edge
  base: ubuntu@24.04
  ssdlc_params:
    name: Charmed Airflow   # product name
    version: "3.1"          # product track
    channel: edge           # risk only

# rock: pulled from the OCI resource of a charm at that channel
- name: airflow-rock
  type: rock
  charm: airflow-api-server-k8s
  charm_resource: airflow-api-server-image
  channel: 3.1/edge
  base: ubuntu@24.04
  ssdlc_params:
    name: Charmed Airflow
    version: "3.1"
    channel: edge
```

`ssdlc_params.cycle` is left unset: SBOMber defaults it to the cycle of the run date.

**Adding a product:** create `sbom_secscan_manifests/<product>.yaml`, then add `<product>` to the `product` input options and to the scheduled list in the workflow.
