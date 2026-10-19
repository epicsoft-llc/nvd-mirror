# nvd-mirror

Static **NVD API datafeed mirror** for [OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/),
plus **ready-made Dependency-Check databases** for H2, MariaDB/MySQL and PostgreSQL.

A daily CI job fetches the NVD changes with vulnz, publishes the datafeed as static `.json.gz` files
on GitLab Pages and loads it into the three databases. Consumers download the feed over plain HTTP —
**no API key, no pagination, no rate limiting** — or start from a database and only fetch the
changes. Operated by [epicsoft LLC](https://epicsoft.one).

* Mirror: https://nvd.epicsoft.one
* Generator: [open-vulnerability-cli (vulnz)](https://github.com/jeremylong/open-vulnerability-cli), image `ghcr.io/jeremylong/open-vulnerability-data-mirror`
* Databases: [OWASP Dependency-Check](https://github.com/dependency-check/DependencyCheck), image `owasp/dependency-check`
* Repository: https://gitlab.com/epicsoft-networks/nvd-mirror, mirrored to [GitHub](https://github.com/epicsoft-llc/nvd-mirror) — issues are welcome on both; code changes only as merge requests on GitLab, the mirror overwrites anything pushed to GitHub
* Changelog: https://gitlab.com/epicsoft-networks/nvd-mirror/-/blob/main/CHANGELOG.md

## Architecture

```
GitLab CI (daily, schedule)
  feed job (image: open-vulnerability-data-mirror / vulnz):
    1. apk upgrade                        -> current packages in the image
    2. seed nvd-cache/ from Pages         -> all-or-nothing, otherwise the job stops
    3. vulnz cve --cache --directory nvd-cache -> fetch only changes
    4. verify every year in cache.properties exists and is valid gzip
  dump:h2, dump:mysql, dump:postgresql (image: owasp/dependency-check, in docker-in-docker):
    5. serve the new feed in the job, load it into a fresh H2, MariaDB 13 or PostgreSQL 18 database
    6. dump it; the MySQL dump is also imported into MySQL LTS as a test
  dump:check: same CVE and KEV counts and state in all three, state = feed, no drop -> db.json
  pages job: feed + dumps (last night's dumps if the new ones fail) -> public/, GitLab Pages deploys it
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

## Databases

Every night Dependency-Check loads the new feed into fresh databases — the CISA catalogue of known
exploited vulnerabilities included — and the dumps go online next to the feed, latest only:

| File | For | Use |
|---|---|---|
| `db/odc.mv.db.gz` | H2, Dependency-Check's built-in database | unpack into the data directory (`--data` of the CLI, `/usr/share/dependency-check/data` in the Docker image) |
| `db/dependencycheck-mysql.sql.gz` | MariaDB and MySQL | `CREATE DATABASE dependencycheck CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`, then `gunzip -c … \| mysql dependencycheck` |
| `db/dependencycheck-postgres.sql.gz` | PostgreSQL | `createdb dependencycheck`, then `gunzip -c … \| psql -d dependencycheck` (a current `psql`: the dump uses `\restrict`) |

Each file has a `.sha256` next to it; `db/db.json` lists the Dependency-Check version and database
schema the files belong to, the state of the data, the CVE and KEV counts and per file the engine,
size and checksum. The files only fit that Dependency-Check version. Accounts and grants are not part
of the SQL dumps — set the database up as in
[Using a Database Server](https://dependency-check.github.io/DependencyCheck/data/database.html).

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
- **Pipeline schedule:** daily `0 2 * * *` (Asia/Tbilisi) on `main`. The pipeline runs only on
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
- The databases are rebuilt from scratch every night (a few minutes each); a failed or inconsistent
  dump never holds back the feed — `pages` then keeps last night's dumps. GitLab Pages allows 1 GB per
  site: the feed takes about 200 MB, the three dumps together about 230 MB.
- The consumer pipeline is triggered only once `verify-published` sees the new `cache.properties`
  live (Pages deploys asynchronously).
- The `.json.gz` files are served **raw** (`Content-Type: application/gzip`, no
  `Content-Encoding`); otherwise clients would decompress them and Dependency-Check would get
  corrupt data. Check: `curl -sI https://nvd.epicsoft.one/nvdcve-2024.json.gz`.
- Search engines: `index.html` has a `noindex` meta tag, `robots.txt` blocks the feed files and
  the dumps (GitLab Pages cannot send custom headers).

## Reporting problems

Issues are welcome on [GitLab](https://gitlab.com/epicsoft-networks/nvd-mirror/-/issues) and
[GitHub](https://github.com/epicsoft-llc/nvd-mirror/issues). Please report a security problem as a
**confidential issue** on GitLab instead of a public one.

## License

[MIT](https://gitlab.com/epicsoft-networks/nvd-mirror/-/blob/main/LICENSE) — Copyright (c) 2026 epicsoft LLC / Alexander Schwarz

The MIT license applies only to files created by epicsoft LLC — the CI configuration, the scripts and the landing
page. The mirrored NVD data and the CISA catalogue are US Government public domain; vulnz, Dependency-Check (whose
database schema the dumps carry) and their images remain under their own licenses, the Inter font in
`public/fonts/` under the SIL Open Font License.
