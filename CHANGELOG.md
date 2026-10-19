# Changelog

All notable changes to the NVD datafeed mirror at https://nvd.epicsoft.one.

The mirror has no version number of its own; entries are dated. The feed format is the one of
[open-vulnerability-cli (vulnz)](https://github.com/jeremylong/open-vulnerability-cli), which the CI runs from the
`latest` image - v9.0.6 on 2026-10-19.

---

## 2026-10-19

### Added

- A mirror on GitHub: https://github.com/epicsoft-llc/nvd-mirror.
- `AGENTS.md` for contributors, and this changelog.

### Changed

- No CI cache any more: every run seeds from the published files (about 200 MB, about a minute) and then fetches the
  NVD changes since. A run whose seed fails stops without publishing, instead of starting a full NVD download that
  does not fit the CI runner.

### Security

- Both CI jobs upgrade the Alpine packages of the vulnz image before they run. The image is only rebuilt with vulnz
  releases, and the one of v9.0.6 from 2026-08-02 shipped OpenSSL 3.5.7, curl 8.21.0 and OpenJDK 17.0.19 - 38
  packages behind their Alpine 3.24 updates. After the upgrade: OpenSSL 3.5.9, curl 8.22.0, OpenJDK 17.0.20.
- Tokens stay off command lines: the seed download and `seed-upload.sh` hand the auth header to curl over stdin,
  `generate-datafeed.sh` passes `NVD_API_KEY` to `docker run` through the environment.
