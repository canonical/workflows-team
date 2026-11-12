# Summary

This action sets up a temporary Gitea repository and configures a Juju `git-integrator` application to use it.

The Gitea repository is created with a user, access token, and initial commit on the configured tracking branch. The action is intended for CI workflows that need a Git provider to test Juju Charms that consume the `git` relation.

# Example usage

Example workflow:

```yaml
name: Demo setup-gitea-action

on:
  workflow_dispatch:

jobs:
  setup-gitea:
    name: Set up Gitea and git-integrator
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Gitea
        id: gitea
        uses: canonical/workflows-team/actions/setup-gitea-action@main
        with:
          model: my-test-model

      - name: Show Gitea repository
        run: |
          echo "Repository: ${{ steps.gitea.outputs.repository-url }}"
```

The action creates a temporary Gitea repository and configures `git-integrator` to use it. The repository URL is available through the `repository-url` output.

# Next steps

- Add support for accepting a user-provided directory containing files to seed the temporary Gitea repository. This would allow workflows with specific use cases to provide the files they need in the repository rather than using only the default test content.
- Add an integration test to the action's workflow using an actual Juju Charm, such as Airflow, to verify that the Gitea-backed `git-integrator` satisfies the Charm's `git` relation.

