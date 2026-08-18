# Overpass Mirror

A self-hosted **Overpass API mirror** of OpenStreetMap for North America, so we can run our
own query endpoint instead of the rate-limited public Overpass instances. This is an
**ops/infra repo** — a Docker Compose stack and shell tooling, not an application codebase.
The roadmap lives in issue [#10](https://github.com/misterbisson/overpass-mirror/issues/10);
operating instructions are in [docs/RUNBOOK.md](docs/RUNBOOK.md); licensing is AGPL-3.0 with a
[NOTICE](NOTICE) covering the served ODbL data.

## Architecture

One self-contained container runs the **entire** engine — there is no external database or
sidecar:

```
Geofabrik north-america-latest.osm.pbf  (17.9 GB extract)
        │  download + transcode (see gotcha #1)
        ▼
init_osm3s → Overpass DB in the named volume  (/db, ~50 GB)
        │
        ├─ dispatcher            (brokers DB access via /db/db/osm3s_osm_base)
        ├─ interpreter (fcgiwrap → nginx)   serves /api/interpreter
        └─ update loop           applies OSM diffs from OVERPASS_DIFF_URL (keeps data current)
```

The image is built from [`Dockerfile`](Dockerfile) = pinned `wiktorn/overpass-api` + `pbzip2`.
The DB lives in the `<project>_overpass-db` **named volume**, never a bind mount (see gotcha
#4). All knobs are documented in [`.env.example`](.env.example) and default to whole North
America.

## Running it

```bash
docker compose -p overpass-na up -d --build      # defaults to North America
curl -s http://localhost:12345/api/status
curl -s --data-urlencode \
  'data=[out:json][timeout:25];nwr(around:800,38.8977,-77.0365)[amenity=cafe];out center;' \
  http://localhost:12345/api/interpreter
```

Host port is **12345** → container 80. To validate the whole pipeline fast, point it at a tiny
extract (imports in ~2 min) instead of the continent:

```bash
OVERPASS_PLANET_URL=https://download.geofabrik.de/north-america/us/district-of-columbia-latest.osm.pbf \
OVERPASS_DIFF_URL=https://download.geofabrik.de/north-america/us/district-of-columbia-updates/ \
OVERPASS_PORT=12346 docker compose -p overpass-smoke up -d
```

## Things not to undo

These are load-bearing fixes for non-obvious failures — each cost real debugging. See the
inline comments where they live.

1. **PBF → bz2 XML transcode** (`OVERPASS_PLANET_PREPROCESS` in `docker-compose.yml`).
   Geofabrik **retired its `.osm.bz2` files** (now 404) and ships PBF only, but the image's
   `init_osm3s.sh` `bzcat`s the planet — it requires bzip2 XML. So we transcode the downloaded
   PBF with `osmium` before init. Without it the container crash-loops on
   `bunzip2: (stdin) is not a bzip2 file`.

2. **`/db` must be traversable** (`initdb.d/00-db-traversable.sh`, `chmod o+rx /db`).
   The interpreter runs as the **`nginx`** user (fcgiwrap), but a named volume at `/db`
   inherits the image's `0700 overpass` perms, so `nginx` can't reach the dispatcher socket and
   **every HTTP query 500s** with `open64: 13 Permission denied .../osm3s_osm_base`. The CLI
   path runs as root, so this only shows over HTTP.

3. **`pbzip2` for the transcode** (`Dockerfile`). The PBF→bz2 transcode is the single largest
   cost of a from-scratch import; the base image ships only single-threaded `bzip2`, which pegs
   one core for hours. `pbzip2` spreads it across all cores; its output is standard bzip2 the
   importer reads unchanged.

4. **Keep the DB on the named volume — do not bind-mount `/db` to a host path.** The DB is
   `mmap`-heavy; macOS bind mounts (gRPC-FUSE) make that slow and fragile. Use the
   backup/restore tarball for portability instead.

5. **`restart: unless-stopped` is required.** The image **exits after init** (it honors
   `OVERPASS_STOP_AFTER_INIT`, whose default exits), and the restart policy is what brings it
   back up serving. On restart, `/db/init_done` already exists so it skips straight to serving —
   it does **not** re-import. (Setting `OVERPASS_STOP_AFTER_INIT=false` would avoid the hop; not
   done yet.)

## Import cost, and staying current

A from-scratch North America import is a **one-time ~14 hr** cost on an 8 GB-RAM / 12-CPU Docker
Desktop VM: download ~1 hr → transcode ~6 hr → DB build ~6 hr → replication baseline. Needs
~130 GB+ host free disk during import (peak); the seeded DB is ~50 GB.

**Staying current never re-imports.** The update loop applies small incremental `.osc.gz`
diffs from `OVERPASS_DIFF_URL` (Geofabrik `north-america-updates/`, daily) directly to the live
DB — tens of MB/day, not the 17.9 GB extract. The transcode problem is a *seeding* artifact and
does not apply to diffs.

## Backup / restore

The ~14 hr build is expensive, so snapshot it. [`scripts/backup.sh`](scripts/backup.sh) tars the
volume to a host tarball (~41 GB); [`scripts/restore.sh`](scripts/restore.sh) restores it into a
fresh volume. A rebuild from snapshot is a few-minute restore vs the full import. Details in
[docs/RUNBOOK.md](docs/RUNBOOK.md).

## Repo conventions

- **Squash-merge only.** The squash commit message = PR **title** + **body**, so both are
  load-bearing: the title must be a Conventional Commit, and release-please parses the message.
- **Conventional Commit PR titles are enforced** by the required `squash message parses` check
  ([`.github/workflows/pr-message.yml`](.github/workflows/pr-message.yml) +
  `.github/scripts/check-pr-message.mjs`), using the same parser release-please uses.
- **Releases** are automated by release-please (`release-type: simple`, `bump-minor-pre-major`).
- **Branch protection on `main`** is solo-friendly: a PR is required, **0 approvals**, required
  checks `ci` + `squash message parses`, no force-push/deletion.

## Build & test

There is no compiler. CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) is a single
always-reporting `ci` job: language-agnostic hygiene plus stack checks that stay dormant until
their files exist — `docker compose config` validation and `shellcheck`. Validate locally the
same way:

```bash
docker compose config --quiet                       # compose schema/interpolation
shellcheck scripts/*.sh initdb.d/*.sh               # shell tooling
docker build -t overpass-mirror:dev .              # the Dockerfile builds
```

Any change touching the actual import should be smoke-tested with the tiny-extract recipe above
before trusting it against the continent.
