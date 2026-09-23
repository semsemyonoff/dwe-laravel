#!/usr/bin/env bash
# Container-start hook for app-main while the otel tool is enabled
# (compose/tools/otel-apps.yml replaces the command with `ensure.sh php-fpm -F`).
#
# Installs the OTel SDK into /opt/otel-php/build/vendor — a vendor dir SEPARATE
# from the app's — then execs the real command. Hash-gated on this directory's
# composer.base.json + the app's composer.lock, so a restart with neither changed
# costs one sha256sum. Non-fatal: a failed install logs a warning and PHP runs
# uninstrumented (prepend.php checks for build/vendor/autoload.php).
#
# Why a generated replace/provide block: resolved on its own, the SDK +
# opentelemetry-auto-laravel pull a SECOND full Laravel (~75 packages, e.g.
# laravel/framework 13.33 next to the app's 13.30, brick/math 1.0 next to
# 0.18). Two copies of one class in two autoloaders is a fatal waiting to
# happen, so every package the app's lock ships is declared as replaced AT THE
# APP'S EXACT VERSION: composer then checks the OTel constraints against what
# the app really has and installs only the OTel-only packages.
set -uo pipefail

src=/opt/otel-php
build="$src/build"
app_lock="${OTEL_PHP_APP_LOCK:-/workspace/src/composer.lock}"

ensure() {
	[ -f "$app_lock" ] || { echo "otel: $app_lock not found; skipping SDK install" >&2; return 1; }
	mkdir -p "$build" || return 1
	local hash
	hash=$(cat "$src/composer.base.json" "$app_lock" | sha256sum | cut -d' ' -f1)
	if [ -f "$build/vendor/autoload.php" ] && [ "$(cat "$build/.hash" 2>/dev/null)" = "$hash" ]; then
		return 0
	fi
	echo "otel: installing PHP SDK into $build (app lock changed or first start)" >&2
	# replace: every real package of the app lock, pinned to its locked version.
	# provide: what those packages themselves replace/provide (laravel/framework
	# replaces illuminate/*, guzzle provides psr/http-client-implementation ...).
	jq --slurpfile lock "$app_lock" '
		($lock[0].packages + ($lock[0]["packages-dev"] // [])) as $pkgs
		| .replace = ($pkgs | map({(.name): .version}) | add)
		| .provide = ($pkgs
			| map(. as $p | ((.replace // {}) + (.provide // {}))
				| to_entries
				| map({(.key): (if .value == "self.version" then $p.version else .value end)}))
			| flatten | add // {})
	' "$src/composer.base.json" >"$build/composer.json" || return 1
	(
		cd "$build" &&
			COMPOSER_NO_AUDIT=1 composer update --no-dev --no-interaction --no-progress \
				--optimize-autoloader --quiet
	) || return 1
	echo "$hash" >"$build/.hash"
}

ensure || echo "otel: PHP SDK install failed; app-main runs uninstrumented" >&2

exec "$@"
