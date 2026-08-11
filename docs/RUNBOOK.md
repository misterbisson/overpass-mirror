# Runbook

Operating the Overpass mirror stack. See [issue #8](https://github.com/misterbisson/overpass-mirror/issues/8) for the broader operational scope.

## Stack

One container (`wiktorn/overpass-api` + `pbzip2`, see [`Dockerfile`](../Dockerfile)) runs the whole engine: interpreter, dispatcher, nginx/fcgiwrap on `/api/interpreter`, and a diff-update loop. The database lives in the `<project>_overpass-db` named volume. Knobs are documented in [`.env.example`](../.env.example).

## Bring it up

```bash
# Defaults to the whole North America extract.
docker compose -p overpass-na up -d --build
```

Query once healthy (default host port `12345`):

```bash
curl -s --data-urlencode \
  'data=[out:json][timeout:25];nwr(around:800,38.8977,-77.0365)[amenity=cafe];out center 5;' \
  http://localhost:12345/api/interpreter
curl -s http://localhost:12345/api/status
```

## Querying the endpoint

The mirror speaks the standard Overpass API, so any Overpass client or handwritten query works — no auth, no rate limit, coverage is **all of North America** (US, Canada, Mexico, Central America, Greenland). Data currency tracks ~1 day behind via the daily diff loop; every response carries `osm3s.timestamp_osm_base` and an ODbL attribution string.

**Base URL.** `http://localhost:12345` on the host. The port binds `0.0.0.0`, so on the same LAN it is also reachable at `http://<host-lan-ip>:12345` (find it with `ipconfig getifaddr en0`). There is no TLS and no public exposure — exposing it beyond the LAN is a separate task ([#5](https://github.com/misterbisson/overpass-mirror/issues/5)).

**Endpoints.**

- `GET /api/status` — dispatcher status and current replication time.
- `POST /api/interpreter` (or `GET`) — run Overpass QL; pass the query in the `data` parameter.

```bash
# POST, form-encoded (the usual way)
curl -s --data-urlencode \
  'data=[out:json][timeout:25];nwr(around:800,38.8977,-77.0365)[amenity=cafe];out center;' \
  http://localhost:12345/api/interpreter

# GET, query in the URL
curl -s 'http://localhost:12345/api/interpreter?data=[out:json];out count;'
```

Cross-continent sanity checks (each returns JSON `elements`; `nwr` = nodes+ways+relations):

```
# US — near the White House, DC
[out:json][timeout:25];nwr(around:800,38.8977,-77.0365)[amenity=cafe];out center;
# Canada — near Toronto CN Tower
[out:json][timeout:25];nwr(around:800,43.6426,-79.3871)[amenity=cafe];out center;
# Mexico — near Mexico City Zócalo
[out:json][timeout:25];nwr(around:800,19.4326,-99.1332)[amenity=cafe];out center;
```

**Gotchas for query authors.**

- Prefix queries with `[out:json]` for JSON (the default output is XML); include a `[timeout:N]`.
- `is_in`/`area{}` queries are **not** supported — area generation is off (`OVERPASS_USE_AREAS=false`). Radius (`around:`), bounding-box, and tag filters all work.

## Cost model (why we snapshot)

A from-scratch import has three costs; on this hardware, for North America:

| Phase | Cost | Notes |
|---|---|---|
| Download 17.9 GB PBF | ~1 hr | network-bound |
| Transcode PBF → bz2 XML | **the big one** | the importer needs bzip2 XML; Geofabrik ships PBF only. `pbzip2` parallelizes it across all cores |
| Build DB (`init_osm3s`) | ~1–3 hr | disk-I/O-bound |

Restarting or recreating the container **reuses the seeded volume** and skips all of this — only `down -v`, `docker volume rm`, or a Docker factory reset wipe it.

## Back up / restore the seeded DB

Turn the multi-hour import into a few-minute restore, and get a portable, backup-able artifact:

```bash
# Snapshot (stops the stack briefly for a consistent tar, then restarts it)
scripts/backup.sh -p overpass-na -o ./backups

# Restore into a fresh volume, then start
scripts/restore.sh ./backups/overpass-na_overpass-db-YYYYmmdd-HHMMSS.tgz -p overpass-na
docker compose -p overpass-na up -d
```

Keep the live DB on the named volume (fast). Do **not** bind-mount `/db` to a host folder — the DB is `mmap`-heavy and macOS bind mounts make that slow and fragile; the tarball is the right portability mechanism.

## Change the region

Point `OVERPASS_PLANET_URL`/`OVERPASS_DIFF_URL` at a matching extract + diff feed (see `.env.example`), then re-init into a fresh volume (`down -v` first).
