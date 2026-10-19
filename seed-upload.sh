#!/bin/bash
set -euo pipefail

# Full rebuild: upload the locally built nvd-cache to the GitLab package registry, then run a web
# pipeline with CI variable SEED_VERSION=<version> (a full build OOMs on the CI runner).
#
#   GITLAB_TOKEN='<PAT with write_package_registry>' ./seed-upload.sh
#
# Optional overrides:
#   SEED_VERSION   package version (default: today's date, YYYYMMDD)
#   CACHE_DIR      source directory (default: ./nvd-cache)
#   GITLAB_API     API base URL (default: https://gitlab.com/api/v4)
#   GITLAB_PROJECT URL-encoded project path or numeric ID (default: epicsoft-networks%2Fnvd-mirror)

GITLAB_TOKEN="${GITLAB_TOKEN:?set GITLAB_TOKEN (GitLab PAT with the write_package_registry scope)}"
SEED_VERSION="${SEED_VERSION:-$(date +%Y%m%d)}"
CACHE_DIR="${CACHE_DIR:-nvd-cache}"
GITLAB_API="${GITLAB_API:-https://gitlab.com/api/v4}"
GITLAB_PROJECT="${GITLAB_PROJECT:-epicsoft-networks%2Fnvd-mirror}"
PKG="nvd-seed"

[ -f "${CACHE_DIR}/cache.properties" ] || {
  echo "ERROR: ${CACHE_DIR}/cache.properties not found -- run ./generate-datafeed.sh first." >&2
  exit 1
}

base="${GITLAB_API}/projects/${GITLAB_PROJECT}/packages/generic/${PKG}/${SEED_VERSION}"
count=0
cd "${CACHE_DIR}"
for f in nvdcve-*.json.gz cache.properties nvdcve-*.meta; do
  [ -e "$f" ] || continue
  echo "uploading ${f} ..."
  # The token goes to curl over stdin, not onto its command line.
  curl -fsSL --header @- \
    --upload-file "$f" \
    "${base}/${f}" >/dev/null <<<"PRIVATE-TOKEN: ${GITLAB_TOKEN}"
  count=$((count + 1))
done

echo "---"
echo "Uploaded ${count} files to ${PKG}/${SEED_VERSION}."
echo "Next: run a web pipeline with CI variable SEED_VERSION=${SEED_VERSION}, then delete the variable and the package."
