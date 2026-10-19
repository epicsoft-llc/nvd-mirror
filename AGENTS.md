# AGENTS.md — NVD datafeed mirror

Guidance for coding agents working in this repository. User documentation lives in [`README.md`](README.md).

This repository is not an application. It is the CI that builds a static **NVD API datafeed mirror** and publishes it
with **GitLab Pages** at `https://nvd.epicsoft.one`.
[OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/) clients download the CVE data as static
`.json.gz` files over HTTP — no NVD API key, no pagination, no rate limiting.

| | |
|---|---|
| Repository | developed on `gitlab.com/epicsoft-networks/nvd-mirror` (branch `main`), mirrored to `github.com/epicsoft-llc/nvd-mirror` |
| Published at | `https://nvd.epicsoft.one` — GitLab Pages, custom domain |
| Generator | vulnz from [open-vulnerability-cli](https://github.com/jeremylong/open-vulnerability-cli), image `ghcr.io/jeremylong/open-vulnerability-data-mirror` |

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

**Generation:** the `pages` job runs `vulnz cve --cache --directory "$CACHE_DIR"` in the
`ghcr.io/jeremylong/open-vulnerability-data-mirror` image (entrypoint overridden, binary at `/usr/local/bin/vulnz`).
Output: `nvdcve-2002.json.gz … nvdcve-<year>.json.gz`, `nvdcve-modified.json.gz`, `nvdcve-*.meta`, `cache.properties`.

**Package upgrade first:** the image is only rebuilt with vulnz releases, so its Alpine packages — OpenSSL, curl, the
JDK — fall behind between them. Both jobs start with `apk --no-cache upgrade`; the image runs as root, which allows
it. Should the image ever leave Alpine, that line fails the job instead of dropping the upgrade unnoticed.

**Incremental runs:** every run seeds `nvd-cache/` from the published files (`$MIRROR_BASE`, about 200 MB), and vulnz
fetches only the changes since. Pages is the only store; there is no CI cache. A failed seed stops the job — a full
NVD download does not fit the runner. A daily run takes a few minutes.

**Publishing:** the files are copied into `public/` and served by GitLab Pages (the job **must** be named `pages` and
expose `public/` as an artifact). `nvd.epicsoft.one` is a DNS-only CNAME at Cloudflare to the unique Pages domain
`nvd-mirror-6dd472.gitlab.io`.

**Consumption:** `--nvdDatafeed https://nvd.epicsoft.one/nvdcve-{0}.json.gz` (`{0}` = year or `modified`). After
publishing, `verify-published` waits until the files are live, then `trigger-dep-check` starts the downstream
pipeline that updates a Dependency-Check database from the mirror.

The `pages` job only runs on the pipeline **schedule** or a manual **web** pipeline, not on push.

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
  `public/robots.txt` (blocks the feed files; `index.html` stays crawlable so the tag is read).
- **Pages deploys asynchronously:** `verify-published` polls `$CI_PAGES_URL/cache.properties` until the new
  `lastModifiedDate` is live; only then does `trigger-dep-check` run.
- **`resource_group: pages`:** one run at a time — parallel runs would fetch the same NVD changes and race for the
  Pages deployment.
- **`.gitattributes` enforces LF** for every file.
- **`public/`:** `index.html`, `robots.txt` and the favicons are versioned; the generated `*.json.gz` / `*.meta` /
  `cache.properties` are gitignored. The `@LAST_UPDATE@` placeholder in `index.html` must stay, the `pages` job fails
  without it.

## Manual setup

CI variable, pipeline schedule, Pages domain and Cloudflare DNS are configured by hand — current values in
`README.md` → *Configuration*.

**GitHub mirror:** a push mirror in the GitLab project settings (Repository → Mirroring repositories) with its own
token — not part of the pipeline. Changes are never pushed to GitHub directly; the mirror would overwrite them.
