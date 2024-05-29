#!/bin/bash

docker compose --env-file settings.txt pull
docker compose --env-file settings.txt up -d
