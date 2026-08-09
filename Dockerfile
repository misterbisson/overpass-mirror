# Extends the pinned wiktorn/overpass-api image with pbzip2 (parallel bzip2).
#
# Why: a from-scratch import must transcode the Geofabrik PBF into the bzip2 XML
# the image's init_osm3s.sh consumes (Geofabrik retired its .osm.bz2 files). The
# base image only ships single-threaded bzip2, which pegs one core and makes the
# transcode the dominant cost of the whole import — hours for North America. Its
# output is standard bzip2, so init_osm3s.sh's `bzcat` reads a pbzip2-produced
# file unchanged; swapping in pbzip2 (see OVERPASS_PLANET_PREPROCESS in
# docker-compose.yml) spreads that work across every core.
#
# Everything else — entrypoint, osmium, services — is inherited untouched.
ARG OVERPASS_IMAGE_TAG=v0.7.62.9
FROM wiktorn/overpass-api:${OVERPASS_IMAGE_TAG}

RUN apt-get update \
 && apt-get install -y --no-install-recommends pbzip2 \
 && rm -rf /var/lib/apt/lists/*
