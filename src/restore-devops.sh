#!/bin/bash

# Define variables
BACKUP_FILE=""
ORGANIZATION=""
PAT=""

# Parse script arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -f|--file)
      BACKUP_FILE="$2"
      shift
      shift
      ;;
    -o|--organization)
      ORGANIZATION="$2"
      shift
      shift
      ;;
    -p|--pat)
      PAT="$2"
      shift
      shift
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]}"

# Check if the backup file is provided
if [[ -z "${BACKUP_FILE}" ]]; then
    echo "ERROR: Backup file not provided. Use -f or --file option."
    exit 1
fi

# Check if the organization URL is provided
if [[ -z "${ORGANIZATION}" ]]; then
    echo "ERROR: Organization URL not provided. Use -o or --organization option."
    exit 1
fi

# Check if the PAT is provided
if [[ -z "${PAT}" ]]; then
    echo "ERROR: PAT not provided. Use -p or --pat option."
    exit 1
fi

# Extract the tar.gz backup file
EXTRACT_DIR=$(basename "${BACKUP_FILE}" .tar.gz)
mkdir -p "${EXTRACT_DIR}"
tar -xzf "${BACKUP_FILE}" -C "${EXTRACT_DIR}"

# Set up Azure DevOps CLI
az extension add --name 'azure-devops'
export AZURE_DEVOPS_EXT_PAT="${PAT}"
B64_PAT=$(printf "%s"":${PAT}" | base64)

# Loop through the projects and repositories
for PROJECT_DIR in "${EXTRACT_DIR}"/*/; do
    PROJECT_NAME=$(basename "${PROJECT_DIR}")
    
    # Check if the project exists, and create it if it doesn't
    if ! az devops project show --organization "${ORGANIZATION}" --project "${PROJECT_NAME}" > /dev/null 2>&1; then
        az devops project create --organization "${ORGANIZATION}" --name "${PROJECT_NAME}" --source-control git --process "Agile"
    fi

    # Loop through the repositories in the current project
    for REPO_DIR in "${PROJECT_DIR}"/*/; do
        REPO_NAME=$(basename "${REPO_DIR}")

        # Check if the repository exists, and create it if it doesn't
        if ! az repos show --organization "${ORGANIZATION}" --project "${PROJECT_NAME}" --repository "${REPO_NAME}" > /dev/null 2>&1; then
            az repos create --organization "${ORGANIZATION}" --project "${PROJECT_NAME}" --name "${REPO_NAME}"
        fi

        # Push the backup repository to the Azure DevOps repository
        pushd "${REPO_DIR}"
        git remote add azure "${ORGANIZATION}/${PROJECT_NAME}/_git/${REPO_NAME}"
        git -c http.extraHeader="Authorization: Basic ${B64_PAT}" push azure --all

        # If the repository has tags, push them as well
        if [ "$(git tag)" ]; then
            git -c http.extraHeader="Authorization: Basic ${B64_PAT}" push azure --tags
        fi
        popd
    done
done

# Clean up the extracted backup directory
rm -rf "${EXTRACT_DIR}"

echo "=== Restore completed ==="
