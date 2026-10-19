#!/bin/bash
set -euo pipefail

# Generate the NVD datafeed locally into ./nvd-cache with vulnz (same output as the pages job).
#
#   NVD_API_KEY='...' ./generate-datafeed.sh      (or DC_APIKEY)

NVD_API_KEY="${NVD_API_KEY:-${DC_APIKEY:-}}"
NVD_API_KEY="$(echo -n "${NVD_API_KEY}" | xargs)"   # strip whitespace
[ -n "${NVD_API_KEY}" ] || { echo "ERROR: NVD_API_KEY (or DC_APIKEY) is not set." >&2; exit 1; }
# docker run takes the key from the environment (-e NVD_API_KEY), so it stays off the command line.
export NVD_API_KEY

IMAGE="ghcr.io/jeremylong/open-vulnerability-data-mirror:latest"
OUT="${PWD}/nvd-cache"
mkdir -p "${OUT}"

# A full build needs a large heap (the CI runner OOMs at 4g). vulnz reads JAVA_OPTS;
# Docker Desktop needs more RAM than -Xmx.
JAVA_OPTS="${JAVA_OPTS:--Xmx8g -XX:+UseStringDeduplication}"

docker run --rm --name nvd-data-mirror \
  -e NVD_API_KEY \
  -e JAVA_OPTS="${JAVA_OPTS}" \
  -e LOGGING_LEVEL_IO_GITHUB_JEREMYLONG="DEBUG" \
  -v "${OUT}:/cache" \
  --entrypoint vulnz "${IMAGE}" \
  cve --cache --directory /cache --delay 6000 --maxRetry 50

echo "---"
echo "Done. Generated files in ${OUT}:"
ls -lh "${OUT}"
echo "Total size:"; du -sh "${OUT}"
