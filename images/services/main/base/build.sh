#!/bin/bash
# Build & push the multi-arch base image for the main Laravel service.
# Usage: ./build.sh [tag]   (tag defaults to "latest"; Makefile passes the PHP version, e.g. 8.5)
# Requires `docker login ghcr.io` with a token that has write:packages scope.

IMAGE_NAME=ghcr.io/semsemyonoff/dwe-laravel-php
VERSION=${1:-latest}

DOCKERFILE_DIR="$(dirname "$0")"

TAG_IMAGE="${IMAGE_NAME}:${VERSION}"

docker buildx create --use --name dwe-builder || docker buildx use dwe-builder
echo "Docker Buildx builder set up."

echo "Building and pushing ${TAG_IMAGE}"
docker buildx build --platform linux/amd64,linux/arm64 -f "${DOCKERFILE_DIR}"/Dockerfile -t "${TAG_IMAGE}" --push "${DOCKERFILE_DIR}"

echo "Remove builder"
docker buildx rm dwe-builder
echo "Builder removed"
