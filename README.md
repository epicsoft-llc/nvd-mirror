# nvd-mirror

Static **NVD API datafeed mirror** for [OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/).

A daily CI job fetches the NVD changes with vulnz and publishes the datafeed as static `.json.gz`
files on GitLab Pages. Consumers download them over plain HTTP — **no API key, no pagination, no
rate limiting**.

## Architecture

```
GitLab CI (daily, schedule)
  pages job (image: open-vulnerability-data-mirror / vulnz):
    1. restore CI cache nvd-cache/        -> incremental
       (cache lost? reseed from Pages -- all-or-nothing, else full download)
    2. vulnz cve --cache --directory nvd-cache -> fetch only changes
    3. verify every year in cache.properties exists and is valid gzip
    4. nvd-cache/*.json.gz + cache.properties -> public/
    5. GitLab Pages deploys public/
  verify-published job: wait for the deployment to go live
  trigger-dep-check job: start the consumer pipeline (epicsoft-networks/dependencycheck)
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

The `dependencycheck` project uses this URL as the default in its CI `Update` job and in
`run-local-df.sh.example` (override: `DC_DATAFEED_URL`).

## Local generation / test

```bash
NVD_API_KEY='<key>' ./generate-datafeed.sh
# produces ./nvd-cache/nvdcve-*.json.gz, nvdcve-modified.json.gz, cache.properties
```

## Full rebuild

Only needed if neither the CI cache nor Pages has the feed (a full build runs out of memory on the
CI runner):

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

- Daily runs are incremental (CI cache; if it is gone, reseeded from the published files) and take
  a few minutes.
- **Reseeding is all-or-nothing:** vulnz never re-downloads a year listed in `cache.properties`, so
  a seed missing one year is discarded. Before publishing, every listed year is checked with
  `gzip -t`.
- The consumer pipeline is triggered only once `verify-published` sees the new `cache.properties`
  live (Pages deploys asynchronously).
- The `.json.gz` files are served **raw** (`Content-Type: application/gzip`, no
  `Content-Encoding`); otherwise clients would decompress them and Dependency-Check would get
  corrupt data. Check: `curl -sI https://nvd.epicsoft.one/nvdcve-2024.json.gz`.
- Search engines: `index.html` has a `noindex` meta tag, `robots.txt` blocks the feed files
  (GitLab Pages cannot send custom headers).

## License

This project's infrastructure (CI, scripts, HTML) is licensed under the [MIT License](LICENSE).
The mirrored NVD data is US Government public domain.
