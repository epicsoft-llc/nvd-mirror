#!/bin/bash
set -euo pipefail

# Locally generate the NVD datafeed into ./nvd-cache via vulnz (open-vulnerability-cli).
# Useful for testing / pre-seeding outside of CI. Produces the same result as the pages job.
#
#   NVD_API_KEY='...' ./generate-datafeed.sh      (or DC_APIKEY)

NVD_API_KEY="${NVD_API_KEY:-${DC_APIKEY:-}}"
NVD_API_KEY="$(echo -n "${NVD_API_KEY}" | xargs)"   # strip whitespace
[ -n "${NVD_API_KEY}" ] || { echo "ERROR: NVD_API_KEY (or DC_APIKEY) is not set." >&2; exit 1; }

IMAGE="ghcr.io/jeremylong/open-vulnerability-data-mirror:latest"
OUT="${PWD}/nvd-cache"
mkdir -p "${OUT}"

# A full NVD build needs a large Java heap; the CI runner is capped at 4g (OOMs), so do the initial
# full build here where more RAM is available. We call vulnz directly (--entrypoint vulnz), so it
# reads JAVA_OPTS (plural). Ensure Docker Desktop's VM has more RAM than -Xmx (e.g. >8g for -Xmx8g).
JAVA_OPTS="${JAVA_OPTS:--Xmx8g -XX:+UseStringDeduplication}"

docker run --rm --name nvd-data-mirror \
  -e NVD_API_KEY="${NVD_API_KEY}" \
  -e JAVA_OPTS="${JAVA_OPTS}" \
  -v "${OUT}:/cache" \
  --entrypoint vulnz "${IMAGE}" \
  cve --cache --directory /cache --delay 6000 --maxRetry 50 --debug

echo "---"
echo "Done. Generated files in ${OUT}:"
ls -lh "${OUT}"
echo "Total size:"; du -sh "${OUT}"
