# AGENTS.md — NVD datafeed mirror

Guidance for coding agents working in this repository. User documentation lives in [`README.md`](README.md).

This repository is not an application. It is the CI that builds a static **NVD API datafeed mirror**, loads it into
ready-made **Dependency-Check databases** (H2, MariaDB/MySQL, PostgreSQL) and publishes both with **GitLab Pages** at
`https://nvd.epicsoft.one`. [OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/) clients download
the CVE data as static `.json.gz` files over HTTP — no NVD API key, no pagination, no rate limiting — or start from a
database dump.

| | |
|---|---|
| Repository | developed on `gitlab.com/epicsoft-networks/nvd-mirror` (branch `main`), mirrored to `github.com/epicsoft-llc/nvd-mirror` |
| Published at | `https://nvd.epicsoft.one` — GitLab Pages, custom domain; the dumps under `/db/` |
| Generator | vulnz from [open-vulnerability-cli](https://github.com/jeremylong/open-vulnerability-cli), image `ghcr.io/jeremylong/open-vulnerability-data-mirror` |
| Databases | `owasp/dependency-check:latest` with `mariadb:13`, `postgres:18` and its own H2; MySQL import tested with `mysql:lts` |

## Rules

- **Public repository, MIT.** No internals in any file: no internal hosts, runner or server names, no credentials, no
  infrastructure details. Before finishing a change, search every published file (`git ls-files` plus new files) for
  such terms.
- **Everything in English** — CI, scripts, comments, README, CHANGELOG, the published `public/` site, commit messages.
- **No attribution lines** — no `Co-Authored-By:` trailer, no "Generated with" line and no session link in files,
  commit messages or merge request texts. `public/index.html` naming vulnz as the generator of the feed is not one.
- **Never commit, push, merge, rebase or tag** — changes stay in the working tree. Proposed commit messages follow
  Conventional Commits (`feat:`, `fix:`, `ci:`, `docs:`, `chore:`).
- **A change users notice gets a `CHANGELOG.md` entry** under a date heading, `## YYYY-MM-DD` — never
  `## [Unreleased]`; the mirror has no version of its own.

## How it works

**Generation:** the `feed` job runs `vulnz cve --cache --directory "$CACHE_DIR"` in the
`ghcr.io/jeremylong/open-vulnerability-data-mirror` image (entrypoint overridden, binary at `/usr/local/bin/vulnz`).
Output, as artifact `feed/`: `nvdcve-2002.json.gz … nvdcve-<year>.json.gz`, `nvdcve-modified.json.gz`, `nvdcve-*.meta`,
`cache.properties`.

**Package upgrade first:** the image is only rebuilt with vulnz releases, so its Alpine packages — OpenSSL, curl, the
JDK — fall behind between them. `feed` and `verify-published` start with `apk --no-cache upgrade`; the image runs as
root, which allows it. Should the image ever leave Alpine, that line fails the job instead of dropping the upgrade
unnoticed. The dump jobs use `owasp/dependency-check` as it is: it only processes public data in throwaway containers.

**Incremental runs:** every run seeds `nvd-cache/` from the published files (`$MIRROR_BASE`, about 200 MB), and vulnz
fetches only the changes since. Pages is the only store; there is no CI cache. A failed seed stops the job — a full
NVD download does not fit the runner. A daily run takes a few minutes.

**Databases:** `dump:h2`, `dump:mysql` and `dump:postgresql` run Dependency-Check against the *new* feed, which is not
live yet: a `busybox` web server in the job's docker-in-docker serves the `feed/` artifact as `http://feed/`. Each job
starts a fresh, throwaway database and builds everything from scratch — a few minutes, so no state is carried from
night to night. The schema comes from Dependency-Check's own `initialize_mysql.sql` / `initialize_postgres.sql` in the
core jar; the throwaway databases use Dependency-Check's default account `dcuser` (MariaDB) or trust authentication as
`postgres`, so no secrets are involved. Each job writes its dump, a `.sha256` and `db/info-<format>.env`.
`dump:check` fails unless all three agree on CVE count, KEV count and `nvd.cache.last.modified`, that state equals the
feed's `lastModifiedDate`, KEV is not empty and the CVE count reaches 99 % of the published `db.json`; then it writes
`db/db.json` and `db/ok`. The dump jobs and `dump:check` are `allow_failure`: a broken dump shows as a warning and never
stops the feed.

**Publishing:** the `pages` job copies `feed/` into `public/` and, with `db/ok`, the new dumps into `public/db/` —
otherwise it downloads last night's dumps from `$MIRROR_BASE/db/` (checked against their `.sha256`), or publishes
without dumps if there are none. GitLab Pages serves `public/` (the job **must** be named `pages` and expose `public/`
as an artifact); `nvd.epicsoft.one` is a DNS-only CNAME at Cloudflare to the unique Pages domain
`nvd-mirror-6dd472.gitlab.io`.

**Consumption:** `--nvdDatafeed https://nvd.epicsoft.one/nvdcve-{0}.json.gz` (`{0}` = year or `modified`). After
publishing, `verify-published` waits until the files are live, then `trigger-dep-check` starts the downstream
pipeline that updates a Dependency-Check database from the mirror.

The pipeline only runs on the **schedule** or a manual **web** pipeline, not on push.

## Full rebuild

Only needed if Pages has lost the feed. A full build runs out of memory on the CI runner (4g), so it is built locally
and seeded via the GitLab generic package registry:

1. `NVD_API_KEY='<key>' ./generate-datafeed.sh` — writes to `./nvd-cache`; Docker Desktop needs more RAM than `-Xmx`.
2. `GITLAB_TOKEN='<PAT with write_package_registry>' ./seed-upload.sh` → package `nvd-seed/<version>`.
3. Run a **web** pipeline with CI variable `SEED_VERSION=<version>`, then delete the variable and the package.

`run-local.sh` (gitignored, values empty) chains steps 1–2.

## Key constraints

- **Serve `.json.gz` raw:** `Content-Type: application/gzip`, no `Content-Encoding: gzip`; otherwise clients
  decompress them and Dependency-Check gets corrupt data. Check: `curl -sI https://nvd.epicsoft.one/nvdcve-2024.json.gz`.
- **vulnz flags:** `--cache --directory <dir>` (not `--cache-directory`); the API key comes from the `NVD_API_KEY`
  env var.
- **`--directory` must be absolute in CI:** vulnz resolves a relative path against `/usr/local/bin`, misses
  `cache.properties` and downloads everything. Hence `CACHE_DIR="$CI_PROJECT_DIR/nvd-cache"`.
- **Seeding is all-or-nothing:** vulnz never re-downloads a year listed in `cache.properties`, so a seed missing one
  `.json.gz` would drop that year for good. `seed_from()` discards incomplete seeds; before publishing, every listed
  year is checked with `gzip -t`. It fetches `cache.properties` first: a deployment that goes live during the seed
  can only make the year files newer than it, and vulnz then fetches those changes again.
- **No `cache:`:** the runner names its cache server in the job log, and the logs of this project are public. Pages
  already holds everything a run needs.
- **Tokens stay off command lines,** where every process on the machine can read them: `fetch()` and `seed-upload.sh`
  hand the auth header to curl over stdin (`--header @-`), `generate-datafeed.sh` passes `-e NVD_API_KEY` without a
  value so docker takes it from the environment.
- **DNS only:** the `nvd` record at Cloudflare stays grey; GitLab issues and renews the Let's Encrypt certificate,
  which does not work behind the Cloudflare proxy.
- **No custom headers on GitLab Pages:** noindex comes from the meta tag in `public/index.html` and from
  `public/robots.txt` (blocks the feed files and `/db/`; `index.html` stays crawlable so the tag is read).
- **Pages deploys asynchronously:** `verify-published` polls `$CI_PAGES_URL/cache.properties` until the new
  `lastModifiedDate` is live; only then does `trigger-dep-check` run.
- **`resource_group: pages`** on `feed` and `pages`: one run at a time — parallel runs would fetch the same NVD changes
  and race for the Pages deployment.
- **1 GB per Pages site:** feed about 200 MB, dumps about 230 MB. At 950 MiB the `pages` job publishes the feed without
  the dumps rather than failing.
- **One dump for MariaDB and MySQL:** the throwaway MariaDB runs with `utf8mb4_unicode_ci` (its default
  `utf8mb4_uca1400_ai_ci` is unknown to MySQL) and a `sql_mode` without `NO_AUTO_CREATE_USER` (removed in MySQL 8);
  the dump loses its first line, MariaDB's sandbox marker `/*M!999999\- … */` that stops the MySQL client, and every
  `DEFINER`. `dump:mysql` imports the result into `mysql:lts` and compares the CVE count. The image only ships MySQL
  Connector/J, so the MariaDB driver comes from Maven Central, checked against its `.sha1`.
- **H2 needs `--data`:** otherwise the CLI derives the data directory from its basedir; the job copies
  `<data>/odc.mv.db` out of the container and counts with the H2 shell of the image.
- **PostgreSQL dumps start with `\restrict`** (pg_dump 18): older `psql` versions do not know it, the page says so.
- **`.gitattributes` enforces LF** for every file.
- **`public/`:** `index.html`, `robots.txt`, the favicons and `fonts/` (Inter with its `OFL.txt`) are versioned; the
  feed and the dumps exist only in the CI. `index.html` carries `@LAST_UPDATE@` plus the database placeholders inside
  `<!-- db:files -->` … `<!-- /db:files -->`; without dumps the `pages` job drops that block and keeps
  `<!-- db:none -->`, with dumps the other way round. A placeholder left over fails the job.

## Manual setup

CI variable, pipeline schedule, Pages domain and Cloudflare DNS are configured by hand — current values in
`README.md` → *Configuration*.

**GitHub mirror:** a push mirror in the GitLab project settings (Repository → Mirroring repositories) with its own
token — not part of the pipeline. Changes are never pushed to GitHub directly; the mirror would overwrite them.
