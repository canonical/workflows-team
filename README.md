# workflows-team

This repository consolidates common tooling, templates, and automation used across the Canonical workflows team. It supports secure artifact delivery, SBOM generation, CI/CD standardization, and SSDLC-aligned compliance workflows

### Automation

SBOM automation and secscan using [SBOMber](https://github.com/canonical/sbomber/).
The CI runs every 6 months and generated SSDLC compliant SBOMs for all artifacts.
Relative Files:
- [View manifest](manifest.yaml)
- [CI workflow](sbom_secscan.yaml)
