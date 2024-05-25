set BUILDPLATE_IMPORTER_PLAYER_ID=%1
docker compose --env-file settings.txt run --rm buildplate-importer
