# nvd-mirror

Static **NVD API datafeed mirror** for [OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/).

A daily CI job fetches the NVD changes with vulnz and publishes the datafeed as static `.json.gz`
files on GitLab Pages. Consumers download them over plain HTTP — **no API key, no pagination, no
rate limiting**. Operated by [epicsoft LLC](https://epicsoft.one).

* Mirror: https://nvd.epicsoft.one
* Generator: [open-vulnerability-cli (vulnz)](https://github.com/jeremylong/open-vulnerability-cli), image `ghcr.io/jeremylong/open-vulnerability-data-mirror`
* Repository: https://gitlab.com/epicsoft-networks/nvd-mirror, mirrored to [GitHub](https://github.com/epicsoft-llc/nvd-mirror) — issues are welcome on both; code changes only as merge requests on GitLab, the mirror overwrites anything pushed to GitHub
* Changelog: https://gitlab.com/epicsoft-networks/nvd-mirror/-/blob/main/CHANGELOG.md

## Architecture

```
GitLab CI (daily, schedule)
  pages job (image: open-vulnerability-data-mirror / vulnz):
    1. apk upgrade                        -> current packages in the image
    2. seed nvd-cache/ from Pages         -> all-or-nothing, otherwise the job stops
    3. vulnz cve --cache --directory nvd-cache -> fetch only changes
    4. verify every year in cache.properties exists and is valid gzip
    5. nvd-cache/*.json.gz + cache.properties -> public/
    6. GitLab Pages deploys public/
  verify-published job: wait for the deployment to go live
  trigger-dep-check job: start the downstream Dependency-Check database update
        |
   GitLab Pages, custom domain nvd.epicsoft.one (DNS at Cloudflare, not proxied)
        |
   Consumer:  dependency-check --nvdDatafeed https://nvd.epicsoft.one/nvdcve-{0}.json.gz
```

## Consumer usage

```bash
dependency-check --updateonly \
  --nvdDatafeed https://nvd.epicsoft.one/nvdcve-{0}.json.gz
```

## Local generation / test

```bash
NVD_API_KEY='<key>' ./generate-datafeed.sh
# produces ./nvd-cache/nvdcve-*.json.gz, nvdcve-modified.json.gz, cache.properties
```

## Full rebuild

Only needed if Pages has lost the feed (a full build runs out of memory on the CI runner):

1. `NVD_API_KEY='<key>' ./generate-datafeed.sh` (local, large heap)
2. `GITLAB_TOKEN='<PAT with write_package_registry>' ./seed-upload.sh` → package `nvd-seed/<version>`
3. Run a web pipeline with CI variable `SEED_VERSION=<version>`, then delete the variable and the
   package.

## Configuration (manual)

- **CI/CD variable** `NVD_API_KEY` (masked, protected).
- **Pipeline schedule:** daily `0 2 * * *` (Asia/Tbilisi) on `main`. The `pages` job runs only on
  the schedule or a manual web pipeline, not on push.
- **GitLab Pages:** custom domain `nvd.epicsoft.one` with automatic Let's Encrypt certificate;
  unique Pages domain `nvd-mirror-6dd472.gitlab.io`.
- **Cloudflare DNS** (zone `epicsoft.one`), both records DNS only (grey):
  - `nvd` CNAME → `nvd-mirror-6dd472.gitlab.io`
  - `_gitlab-pages-verification-code.nvd` TXT (GitLab domain verification)

## Notes

- Daily runs are incremental: each one seeds from the published files (about 200 MB) and fetches
  only the NVD changes since; a run takes a few minutes. There is no CI cache.
- The vulnz image is only rebuilt with vulnz releases, so its Alpine packages fall behind between
  them. Both jobs run `apk upgrade` first and work with current OpenSSL, curl and JDK packages.
- Tokens stay off command lines: the scripts and the CI hand them to `curl` and `docker run` over
  stdin or the environment.
- **Seeding is all-or-nothing:** vulnz never re-downloads a year listed in `cache.properties`, so
  a seed missing one year is discarded and the run stops without publishing — a full NVD download
  does not fit the CI runner. Before publishing, every listed year is checked with `gzip -t`.
- The consumer pipeline is triggered only once `verify-published` sees the new `cache.properties`
  live (Pages deploys asynchronously).
- The `.json.gz` files are served **raw** (`Content-Type: application/gzip`, no
  `Content-Encoding`); otherwise clients would decompress them and Dependency-Check would get
  corrupt data. Check: `curl -sI https://nvd.epicsoft.one/nvdcve-2024.json.gz`.
- Search engines: `index.html` has a `noindex` meta tag, `robots.txt` blocks the feed files
  (GitLab Pages cannot send custom headers).

## Reporting problems

Issues are welcome on [GitLab](https://gitlab.com/epicsoft-networks/nvd-mirror/-/issues) and
[GitHub](https://github.com/epicsoft-llc/nvd-mirror/issues). Please report a security problem as a
**confidential issue** on GitLab instead of a public one.

## License

[MIT](https://gitlab.com/epicsoft-networks/nvd-mirror/-/blob/main/LICENSE) — Copyright (c) 2026 epicsoft LLC / Alexander Schwarz

The MIT license applies only to files created by epicsoft LLC — the CI configuration, the scripts and the landing
page. The mirrored NVD data is US Government public domain; vulnz and its image remain under their own licenses.
