#!/usr/bin/env bash
#
# Snapshot the seeded Overpass DB volume to a host tarball.
#
# The expensive part of standing up this mirror is the one-time PBF->bz2 XML
# transcode and DB build (hours for North America). This captures the finished
# DB so a rebuild — or a move to another machine, or recovery from a Docker
# reset — is a few-minute restore (see restore.sh) instead of the full re-import.
#
# For a consistent snapshot the compose stack is stopped for the duration of the
# tar (the update loop writes to the DB while running) and restarted after,
# unless --no-stop is given.
#
# Usage:
#   scripts/backup.sh [-p PROJECT] [-o OUTDIR] [--no-stop]
# Defaults: PROJECT=overpass-na, OUTDIR=./backups
set -euo pipefail

PROJECT="overpass-na"
OUTDIR="./backups"
STOP=1

while [ $# -gt 0 ]; do
	case "$1" in
	-p) PROJECT="$2"; shift 2 ;;
	-o) OUTDIR="$2"; shift 2 ;;
	--no-stop) STOP=0; shift ;;
	-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
	*) echo "Unknown argument: $1" >&2; exit 2 ;;
	esac
done

VOL="${PROJECT}_overpass-db"
if ! docker volume inspect "$VOL" >/dev/null 2>&1; then
	echo "Volume $VOL not found. Is the stack up under project '$PROJECT'?" >&2
	exit 1
fi

mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="${VOL}-${STAMP}.tgz"

if [ "$STOP" -eq 1 ]; then
	echo "Stopping project '$PROJECT' for a consistent snapshot..."
	docker compose -p "$PROJECT" stop
fi

echo "Writing ${OUTDIR}/${ARCHIVE} ..."
docker run --rm \
	-v "${VOL}":/db:ro \
	-v "${OUTDIR}":/backup \
	alpine sh -c "tar czf /backup/${ARCHIVE} -C /db ."

if [ "$STOP" -eq 1 ]; then
	echo "Restarting project '$PROJECT'..."
	docker compose -p "$PROJECT" start
fi

echo "Done: ${OUTDIR}/${ARCHIVE}"
du -h "${OUTDIR}/${ARCHIVE}"
