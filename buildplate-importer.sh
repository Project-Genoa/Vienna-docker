#!/bin/bash

docker compose --env-file settings.txt pull buildplate-importer --include-deps
BUILDPLATE_IMPORTER_PLAYER_ID=$1 docker compose --env-file settings.txt run --rm buildplate-importer
