#!/usr/bin/env bash
#
# Restore a DB snapshot (from backup.sh) into a named volume, skipping the
# multi-hour re-import. On next `docker compose up` the entrypoint sees
# /db/init_done in the restored volume and goes straight to serving.
#
# Refuses to clobber a non-empty target volume unless --force is given.
#
# Usage:
#   scripts/restore.sh ARCHIVE.tgz [-p PROJECT] [--force]
# Defaults: PROJECT=overpass-na
set -euo pipefail

FORCE=0
PROJECT="overpass-na"
ARCHIVE=""

while [ $# -gt 0 ]; do
	case "$1" in
	-p) PROJECT="$2"; shift 2 ;;
	--force) FORCE=1; shift ;;
	-h|--help) sed -n '2,15p' "$0"; exit 0 ;;
	-*) echo "Unknown argument: $1" >&2; exit 2 ;;
	*) ARCHIVE="$1"; shift ;;
	esac
done

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
	echo "Provide a readable archive path. See --help." >&2
	exit 2
fi

VOL="${PROJECT}_overpass-db"
ARCHIVE_DIR="$(cd "$(dirname "$ARCHIVE")" && pwd)"
ARCHIVE_BASE="$(basename "$ARCHIVE")"

docker volume create "$VOL" >/dev/null

# Guard against overwriting a populated volume.
NONEMPTY="$(docker run --rm -v "${VOL}":/db alpine sh -c 'ls -A /db 2>/dev/null | head -1')"
if [ -n "$NONEMPTY" ] && [ "$FORCE" -ne 1 ]; then
	echo "Volume $VOL is not empty. Re-run with --force to overwrite it." >&2
	exit 1
fi

echo "Restoring ${ARCHIVE_BASE} into ${VOL} ..."
docker run --rm \
	-v "${VOL}":/db \
	-v "${ARCHIVE_DIR}":/backup:ro \
	alpine sh -c "rm -rf /db/* /db/..?* /db/.[!.]* 2>/dev/null; tar xzf /backup/${ARCHIVE_BASE} -C /db"

echo "Done. Start with: docker compose -p ${PROJECT} up -d"
