# nvd-mirror

Static **NVD API datafeed mirror** for [OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/).

Dependency-Check normally updates its CVE data through the NVD **API** — many paginated calls that
NVD/Cloudflare throttle with `503` (a full run took us **>6 h**). This mirror generates the datafeed
**once, centrally** and serves it as static `.json.gz` files. Consumers pull them over plain HTTP-GET
— **no API key, no pagination, no rate limiting**, update in minutes.

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
  verify-published job: wait for the deployment to go live, purge the Cloudflare edge
        |
   Cloudflare Free (subdomain nvd.epicsoft.one, Cache Rule *.json.gz)
        |
   Consumer:  dependency-check --nvdDatafeed https://nvd.epicsoft.one/nvdcve-{0}.json.gz
```

## Consumer usage

```bash
dependency-check --updateonly \
  --nvdDatafeed https://nvd.epicsoft.one/nvdcve-{0}.json.gz
```

In the sibling `dependencycheck` project this maps to `run-local-df.sh` resp. the CI `Update` job
(`DC_DATAFEED_URL='https://nvd.epicsoft.one/nvdcve-{0}.json.gz'`).

## Local generation / test

```bash
NVD_API_KEY='<key>' ./generate-datafeed.sh
# produces ./nvd-cache/nvdcve-*.json.gz, nvdcve-modified.json.gz, cache.properties
```

## One-time setup (manual)

1. **CI/CD variable** `NVD_API_KEY` (Settings → CI/CD → Variables; *masked*, no whitespace).
2. **Pipeline schedule** (Settings → CI/CD → Pipeline schedules) → daily, target `main`.
   (The `pages` job only runs on `schedule` or a manual web trigger.)
3. **GitLab Pages custom domain** (Deploy → Pages → New Domain): `nvd.epicsoft.one` →
   GitLab returns a **TXT verification record** and the CNAME target `epicsoft-networks.gitlab.io`.
4. **Cloudflare DNS:**
   - Add the TXT verification record (**DNS only / grey**).
   - Add `nvd` as a **CNAME → `epicsoft-networks.gitlab.io`**.
   - **TLS:** keep it **grey** first until GitLab has issued the Let's Encrypt certificate, then
     switch to **orange** (proxied). SSL/TLS mode **Full (strict)**. *Never* "Flexible".
5. **Cloudflare Cache Rule:** when the URI path ends with `.json.gz` → *Eligible for cache*,
   Edge TTL *Respect origin*.
6. **Optional CI/CD variables** `CF_ZONE_ID` + `CF_API_TOKEN` (API token scope *Zone → Cache Purge*):
   the `verify-published` job purges the Cloudflare edge after each deploy. Without them the edge
   keeps serving the previous files until the `_headers` TTL expires — the consumer pipeline may
   then update against yesterday's data.

## Notes

- The **first CI run** downloads the full NVD (slower, hence `timeout: 3h`); subsequent runs are
  incremental via the CI cache.
- **Seeding is all-or-nothing.** `cache.properties` holds a `lastModifiedDate` per year, so vulnz
  skips any year listed there. If a reseed fetched `cache.properties` but lost a single `.json.gz`,
  that year would never be regenerated and would silently disappear from the mirror — so a partial
  seed is discarded and a full download is done instead. Before publishing, the job additionally
  `gzip -t`s every year that `cache.properties` lists and fails rather than publish a gap.
- The consumer pipeline is triggered only after `verify-published` has seen the new
  `cache.properties` live on the Pages origin (the deployment is asynchronous) and purged the
  Cloudflare edge.
- The `.json.gz` files must be served **raw** (`Content-Type: application/gzip`, **no**
  `Content-Encoding: gzip`) — otherwise Cloudflare/clients decompress them and Dependency-Check
  receives corrupt data. Verify with `curl -sI https://nvd.epicsoft.one/nvdcve-2024.json.gz`.
- NVD data is US Government public domain → redistribution is permitted.

## License

This project's infrastructure (CI, scripts, HTML) is licensed under the [MIT License](LICENSE).
The mirrored NVD data is US Government public domain.
