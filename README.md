# overpass-mirror

Tooling to self-host a **regional [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API)
mirror** of OpenStreetMap data — scoped to a geographic extract (e.g. the United States),
kept continuously up to date from upstream.

It exists so an application with steady, bursty, or heavy Overpass demand can run its own
endpoint instead of leaning on the shared public instances, which enforce a fair-use ceiling
(roughly 10,000 requests/day and <1 GB/day) and **shed heavy users first**. Running your own
instance is the OpenStreetMap project's own recommended answer to sustained demand — not a
workaround.

Beyond avoiding rate limits, a private mirror keeps location-bearing queries on infrastructure
you control rather than sending every lookup to a third-party server.

> **Status: bootstrapping.** This repo currently carries the project's licensing and
> attribution. The deployment manifests described below are the intended design; see the
> roadmap at the bottom.

## How it works

```
Geofabrik / OSM-France (upstream OSM extracts + diffs)
        │  init: regional .osm.pbf        │  updates: minute/day diffs (.osc.gz)
        ▼                                  ▼
   Overpass API engine (wiktorn/overpass-api Docker image)
        │  HTTP POST /api/interpreter  (Overpass QL → JSON)
        ▼
   your application
```

- **Data source.** A [Geofabrik](https://download.geofabrik.de/) regional extract — for a
  US-only mirror, `us-latest.osm.pbf` (~11 GB), far smaller than the ~80 GB planet the public
  instances carry. Smaller sub-region extracts (US West/South/Northeast) are available if you
  want to shrink further.
- **Engine.** The [`wiktorn/overpass-api`](https://github.com/wiktorn/Overpass-API) Docker
  image, initialized from the extract with `--meta=no` (no history/attic → smaller, faster).
  Expect roughly a 20–40 GB database for the US; provision ~100 GB of SSD/NVMe and 8 GB of RAM.
  Overpass is I/O-bound, so fast disk matters more than CPU.
- **Staying current.** The container applies upstream diffs on a loop via `OVERPASS_DIFF_URL`:
  - **Minutely** — [OSM-France](https://download.openstreetmap.fr/replication/) regional
    replication (`.../replication/north-america/us/minute/`) keeps the standard updater happy
    at fine granularity.
  - **Daily** — [Geofabrik](https://download.geofabrik.de/north-america/us-updates/) regional
    diffs are simpler and more than fresh enough for POI-style data.

## Intended quick start

```yaml
# docker-compose.yml (planned)
services:
  overpass:
    image: wiktorn/overpass-api:latest
    environment:
      OVERPASS_MODE: init
      OVERPASS_PLANET_URL: https://download.geofabrik.de/north-america/us-latest.osm.pbf
      OVERPASS_DIFF_URL: https://download.openstreetmap.fr/replication/north-america/us/minute/
      OVERPASS_META: "no"
      OVERPASS_RULES_LOAD: "10"
    volumes:
      - overpass-db:/db
    ports:
      - "12345:80"
volumes:
  overpass-db:
```

The initial import is the slow step (hours); once seeded, `OVERPASS_MODE=clone` on subsequent
starts reuses the database and only applies diffs. Point your application's Overpass endpoint at
`http://<host>:12345/api/interpreter`.

## Roadmap

- [ ] `docker-compose.yml` + init/update configuration
- [ ] Deployment notes (VPS sizing, or a home always-on box behind a tunnel)
- [ ] A safe way to expose the endpoint (Cloudflare Tunnel / Tailscale + a shared secret)
- [ ] Optional thin caching/auth proxy in front of the engine

## Licensing

Two layers, deliberately separate:

- **The code in this repository** — the deployment tooling, scripts, and configuration — is
  licensed under the **[GNU Affero General Public License v3.0](LICENSE)** (AGPL-3.0). AGPL is
  also the license of the Overpass API engine itself, so this stays frictionless if the tooling
  ever vendors or patches Overpass.
- **The OpenStreetMap data** this tooling downloads, builds into a database, and serves is
  licensed by its authors under the **[Open Database License (ODbL) v1.0](https://opendatacommons.org/licenses/odbl/1-0/)**.
  That license is inherited from upstream and is not ours to change. Any database you build or
  endpoint you expose with this tooling must carry OpenStreetMap attribution and remain under
  ODbL share-alike:

  > Map data © OpenStreetMap contributors, available under the
  > [Open Database License](https://www.openstreetmap.org/copyright).

See [`NOTICE`](NOTICE) for full third-party attributions.
