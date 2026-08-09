#!/bin/sh
# Runs on every boot via the image's /docker-entrypoint-initdb.d hook, before
# init and before the services start.
#
# The interpreter CGI runs as the nginx user (fcgiwrap is user=nginx in this
# image), and to answer a query it must open the dispatcher socket at
# /db/db/osm3s_osm_base. A named volume mounted at /db inherits the image's
# 0700 overpass-owned perms, so nginx cannot even traverse /db, and every HTTP
# query fails with:
#
#   runtime error: open64: 13 Permission denied /db/db//osm3s_osm_base
#
# (The engine itself is fine — you only see this over HTTP, because the CLI path
# runs as root.) Making the /db mount root traversable by other users fixes it
# without loosening the DB files inside. /db/db and the socket are already
# group/other-accessible, so o+rx on /db alone is sufficient. Idempotent.
chmod o+rx /db 2>/dev/null || true
