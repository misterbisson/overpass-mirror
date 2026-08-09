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
