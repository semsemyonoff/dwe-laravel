# Image build helpers. Day-to-day lifecycle goes through `dwe` directly.
#
# PHP base image tag (also the image registry tag), e.g. 8.5
PHP_VERSION ?= 8.5

.PHONY: build-php-base-image

# Build & push the multi-arch base PHP image for the main Laravel service
# to ghcr.io/semsemyonoff/dwe-laravel-php. Requires `docker login ghcr.io`.
build-php-base-image:
	@bash images/services/main/base/build.sh $(PHP_VERSION)
