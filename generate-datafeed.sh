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

docker run --rm \
  -e NVD_API_KEY="${NVD_API_KEY}" \
  -v "${OUT}:/cache" \
  --entrypoint vulnz "${IMAGE}" \
  cve --cache --directory /cache --delay 2000 --maxRetry 50

echo "---"
echo "Done. Generated files in ${OUT}:"
ls -lh "${OUT}"
echo "Total size:"; du -sh "${OUT}"
