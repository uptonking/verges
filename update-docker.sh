#!/bin/bash

date

# backup container version
date >> bak/docker-image-versions.txt
docker images >> bak/docker-image-versions.txt

# Pull latest version``
docker compose pull

# Stop and remove older version
docker compose down

# Start the container
docker compose up -d