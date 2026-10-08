# Copyright 2026 Canonical Ltd.
#
# See LICENSE file for licensing details.

set shell := ["bash", "-uc"]


# Build a rock from the requested rock directory.
pack rock_directory:
    cd "{{ rock_directory }}" && rockcraft pack


# Generate the OCI Factory manifest and either:
# - create a local commit for a dry run, or
# - push a signed commit and open an OCI Factory PR.
release-oci-factory rock_directory source_repository source_commit support="minor" risk="stable" dry_run="false":
    #!/usr/bin/env bash
    set -euo pipefail

    rock_directory="{{ rock_directory }}"
    source_repository="{{ source_repository }}"
    source_commit="{{ source_commit }}"
    support="{{ support }}"
    risk="{{ risk }}"
    dry_run="{{ dry_run }}"

    rock_directory="${rock_directory#./}"
    rock_directory="${rock_directory%/}"

    if [[ ! -f "$rock_directory/rockcraft.yaml" ]]; then
        echo "Error: $rock_directory/rockcraft.yaml does not exist" >&2
        exit 1
    fi

    if ! compgen -G "$rock_directory/*.rock" > /dev/null; then
        echo "Error: no packed rock found in $rock_directory" >&2
        echo "Run the pack recipe before release-oci-factory." >&2
        exit 1
    fi

    rockcraft_file="$rock_directory/rockcraft.yaml"

    rock_name="$(yq -r '.name // ""' "$rockcraft_file")"
    rock_version="$(yq -r '.version // ""' "$rockcraft_file")"
    rock_base="$(yq -r '.base // ""' "$rockcraft_file")"

    if [[ "$rock_base" == "bare" ]]; then
        rock_base="$(yq -r '.["build-base"] // ""' "$rockcraft_file")"
    fi

    rock_base="${rock_base##*@}"

    if [[ -z "$rock_name" || -z "$rock_version" || -z "$rock_base" ]]; then
        echo "Error: could not determine rock name, version, or base" >&2
        exit 1
    fi

    directory_version="$(basename "$rock_directory")"

    # Allow directories such as 1.24 to contain patch versions such as 1.24.2.
    if [[ "$directory_version" != "$rock_version" &&
          "$rock_version" != "$directory_version".* ]]; then
        echo "Error: directory version ($directory_version) does not match rock version ($rock_version)" >&2
        exit 1
    fi

    directory_prefix="$(dirname "$rock_directory")"

    if [[ "$directory_prefix" == "." ]]; then
        directory_prefix=""
    fi

    source_root="$PWD"

    echo "Rock name: $rock_name"
    echo "Rock version: $rock_version"
    echo "Rock base: $rock_base"
    echo "Rock directory: $rock_directory"
    echo "Directory prefix: $directory_prefix"
    echo "Source repository: $source_repository"
    echo "Source commit: $source_commit"

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    oci_dir="$tmp_dir/oci-factory"

    if [[ "$dry_run" == "true" ]]; then
        echo "Dry run: cloning canonical/oci-factory"

        git clone --depth 1 \
            https://github.com/canonical/oci-factory.git \
            "$oci_dir"
    else
        if [[ -z "${GH_TOKEN:-}" ]]; then
            echo "Error: GH_TOKEN is not configured" >&2
            exit 1
        fi

        if [[ -z "${OCI_FACTORY_BOT_USERNAME:-}" ]]; then
            echo "Error: OCI_FACTORY_BOT_USERNAME is not configured" >&2
            exit 1
        fi

        if [[ -z "${OCI_FACTORY_BOT_EMAIL:-}" ]]; then
            echo "Error: OCI_FACTORY_BOT_EMAIL is not configured" >&2
            exit 1
        fi

        echo "Syncing ${OCI_FACTORY_BOT_USERNAME}/oci-factory"

        gh repo sync --force \
            "${OCI_FACTORY_BOT_USERNAME}/oci-factory"

        git clone \
            "https://github.com/${OCI_FACTORY_BOT_USERNAME}/oci-factory" \
            "$oci_dir"
    fi

    manifest_file="$oci_dir/oci/$rock_name/image.yaml"
    mkdir -p "$(dirname "$manifest_file")"

    noctua_args=(
        rock manifest "$source_repository"
        "--commit=$source_commit"
        "--base=$rock_base"
        "--support=$support"
        "--risk=$risk"
        "--version=$rock_version"
    )

    # Noctua expects to run from the directory containing the version folders.
    # For example:
    #
    # temporal-ui/2.52.1
    #
    # becomes:
    #
    # working directory: temporal-ui
    # --directory=temporal-ui
    if [[ -n "$directory_prefix" ]]; then
        noctua_args+=("--directory=$directory_prefix")
        cd "$source_root/$directory_prefix"
    else
        cd "$source_root"
    fi

    uvx --from=git+https://github.com/lucabello/noctua \
        noctua "${noctua_args[@]}" \
        | tee "$manifest_file"

    upload_count="$(cat "$manifest_file" | yq '.upload | length')"

    if [[ "$upload_count" -eq 0 ]]; then
        echo "Nothing to update in OCI Factory"
        exit 0
    fi

    cd "$oci_dir"

    echo
    echo "OCI Factory change:"
    git status --short
    git diff -- "oci/$rock_name/image.yaml"

    if [[ -z "$(git status --porcelain -- "oci/$rock_name/image.yaml")" ]]; then
        echo "OCI Factory manifest is already up to date"
        exit 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        git config user.name "workflows-team-ci"
        git config user.email "workflows-team-ci@users.noreply.github.com"

        git checkout -b "dry-run-$rock_name"
        git add "oci/$rock_name/image.yaml"

        git commit \
            --no-gpg-sign \
            -m "chore: Add new $rock_name releases"

        echo
        echo "Dry-run commit:"
        git show --stat --oneline HEAD

        echo
        echo "Dry run complete; nothing was pushed."

        exit 0
    fi

    git config user.name "$OCI_FACTORY_BOT_USERNAME"
    git config user.email "$OCI_FACTORY_BOT_EMAIL"

    git remote set-url origin \
        "https://x-access-token:${GH_TOKEN}@github.com/${OCI_FACTORY_BOT_USERNAME}/oci-factory.git"

    branch_name="update-$(date +%s)"

    git checkout -b "$branch_name"
    git add "oci/$rock_name/image.yaml"

    git commit \
        -m "chore: Add new $rock_name releases"

    git push -u origin "$branch_name" --force

    gh pr create \
        --repo canonical/oci-factory \
        --head "${OCI_FACTORY_BOT_USERNAME}:${branch_name}" \
        --title "chore: Add new $rock_name releases" \
        --body "This is an automatic PR opened by the Workflow Charmers bot."

    echo "OCI Factory PR created."