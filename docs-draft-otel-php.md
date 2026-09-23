### PHP (php-fpm, Laravel) — no app diff, one image line

PHP auto-instrumentation has two halves: the `opentelemetry` C extension (the hook engine, which cannot be installed at runtime) and the SDK plus instrumentation packages (Composer). The recipe keeps both out of the app repo. The extension is built into the image but not enabled. The packages go into a vendor directory of their own under the workspace, and a single `auto_prepend_file` loads them. The overlay mounts the ini that enables both, so with the tool off PHP runs exactly as before.

**Image — build the extension, do not enable it** (the same pattern the official image's users already follow for xdebug):

```dockerfile
# pecl needs phpize + a compiler; the Debian php:*-fpm images keep both.
ARG OTEL_EXT_VER=1.4.2
RUN pecl install -o -f opentelemetry-${OTEL_EXT_VER} && rm -rf /tmp/pear
# No docker-php-ext-enable: no conf.d ini, so the .so is never loaded.
```

The image grows by ~180 KB. Rebuild it yourself (`dwe docker build <service>`): `dwe run` and `services enable --apply` do not rebuild. Do not enable the extension in the image "because it is harmless". With no hooks registered it still costs ~25% on a microbenchmark of user-function calls (the observer API is installed as soon as the extension loads).

**Packages — a sidecar vendor dir, not the app's `composer.json`:**

```text
workspace/otel/php/
  composer.base.json   # sdk, exporter-otlp, opentelemetry-auto-laravel, opentelemetry-auto-pdo
  ensure.sh            # hash-gated composer update into build/, then exec "$@"
  prepend.php          # auto_prepend_file: app autoloader first, then build/vendor
  otel.ini             # extension=opentelemetry + auto_prepend_file
  .gitignore           # build/
```

Resolved on its own, `opentelemetry-auto-laravel` requires `laravel/framework`, and Composer installs a **second full Laravel** (~75 packages) next to the app's, some of them at different versions (in the test project, laravel/framework 13.33 vs 13.30 and brick/math 1.0 vs 0.18). Two copies of one class behind two autoloaders is a fatal error waiting for the first class that differs. `ensure.sh` therefore generates `build/composer.json` from `composer.base.json` plus the app's `composer.lock`. Every locked package goes under `replace` **at its exact locked version**, and what those packages replace or provide goes under `provide` (`illuminate/*`, `psr/http-client-implementation`, …):

```bash
jq --slurpfile lock "$app_lock" '
  ($lock[0].packages + ($lock[0]["packages-dev"] // [])) as $pkgs
  | .replace = ($pkgs | map({(.name): .version}) | add)
  | .provide = ($pkgs | map(. as $p | ((.replace // {}) + (.provide // {}))
      | to_entries | map({(.key): (if .value == "self.version" then $p.version else .value end)}))
      | flatten | add // {})
' composer.base.json > build/composer.json
composer update --no-dev --no-interaction --quiet --working-dir=build
```

Composer then checks the OTel packages' constraints against the versions the app really has. It installs only the OTel-only packages (13 in the test project: `open-telemetry/*`, `google/protobuf`, `php-http/discovery`, `nyholm/psr7-server`, `tbachert/spi`, `composer/semver`). The hash covers `composer.base.json` and the app lock, so a restart with neither changed skips Composer, and a `composer update` in the app re-resolves on the next start. The price: the first start after a lock change needs Packagist, and the sidecar has no committed lock of its own. Allow the `tbachert/spi` plugin: the SDK finds its exporter and instrumentations through it.

`prepend.php` has to load the **app's** autoloader before the sidecar's. The sidecar holds no psr/guzzle/polyfill classes, and the SDK's bootstrap files need them at once. Requiring `vendor/autoload.php` twice is safe, because Composer's `getLoader()` returns the cached loader when `public/index.php` requires it again. Scope it to php-fpm and `artisan`. The ini reaches every PHP process in the container, and loading the app's vendor into `composer`'s own process mixes two Symfony Console versions:

```php
<?php
(static function (): void {
    $sapi = PHP_SAPI;
    $script = (string) ($_SERVER['SCRIPT_FILENAME'] ?? '');
    if ($sapi !== 'fpm-fcgi' && !($sapi === 'cli' && basename($script) === 'artisan')) {
        return;
    }
    $app = '/workspace/src/vendor/autoload.php';
    $otel = __DIR__ . '/build/vendor/autoload.php';
    if (!extension_loaded('opentelemetry') || !is_file($app) || !is_file($otel)) {
        return;
    }
    // queue:listen re-spawns `queue:work --once` every few seconds: drop root
    // spans there, keep jobs (they carry the dispatcher's traceparent).
    if ($sapi === 'cli' && in_array($_SERVER['argv'][1] ?? '', ['queue:work', 'queue:listen'], true)
        && getenv('OTEL_TRACES_SAMPLER') === false) {
        putenv('OTEL_TRACES_SAMPLER=parentbased_always_off');
    }
    require $app;
    require $otel;
})();
```

**The patch:**

```yaml
# compose/otel-apps.yml (compose_after:)
  app:
    command: ["/opt/otel-php/ensure.sh", "php-fpm", "-F"]   # the image ENTRYPOINT still runs first
    volumes:
      - ./workspace/otel/php:/opt/otel-php                  # rw: ensure.sh writes build/
      - ./workspace/otel/php/otel.ini:/usr/local/etc/php/conf.d/zz-otel.ini:ro
    environment:
      OTEL_PHP_AUTOLOAD_ENABLED: "true"
      OTEL_SERVICE_NAME: "app"
      OTEL_RESOURCE_ATTRIBUTES: "service.namespace=${COMPOSE_PROJECT_NAME},deployment.environment.name=dev"
      OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel:4318"
      OTEL_EXPORTER_OTLP_PROTOCOL: "http/protobuf"
      OTEL_TRACES_EXPORTER: "otlp"
      OTEL_METRICS_EXPORTER: "none"
      OTEL_LOGS_EXPORTER: "none"
      OTEL_PROPAGATORS: "tracecontext,baggage"
      OTEL_PHP_DISABLED_INSTRUMENTATIONS: "pdo"
```

`command:` is a whole-value key, which is why the patch belongs in `compose_after:`. `OTEL_BSP_SCHEDULE_DELAY` does nothing under php-fpm: every request builds a fresh SDK, and the batch processor flushes in the request's shutdown handler. Laravel's `Response::send()` calls `fastcgi_finish_request()` first, so the client does not wait for the export, but the FPM worker does. Metrics are `none` for the same reason: a periodic reader never ticks inside one request. RED panels come from Tempo's span metrics.

**What you get** (`dwe cmd otel.traces -- show <id>`):

```text
+0ns  11.5ms  GET / [server]  GET / -> 200
  ×2  total=1.9ms  avg=965µs  max=1.5ms  sql SELECT  select * from `sessions` where `id` = ? limit ?
  +10.1ms  610µs  sql INSERT [client]  insert into `sessions` (`payload`, `last_activity`, …) values (?, ?, ?, ?, ?, ?)
```

The server span carries `http.route` (checked only on `/` in the test project). SQL spans use the new keys (`db.system.name`, `db.query.text`, `db.operation.name`), with placeholders, not values. `php artisan <cmd>` gives a `Command <name>` root span. A queued job shows up as a `process` consumer span **inside the trace that dispatched it**, because Laravel carries `traceparent` in the job payload. The full stack added ~4–5 ms at p50 to a 11 ms Laravel welcome page.

Traps:

- **One DB layer.** `opentelemetry-auto-laravel` already emits one `sql <VERB>` span per query. With `auto-pdo` also active, each statement gains `PDO::prepare`, `PDOStatement::execute` and `fetchAll` siblings (4–5 spans per query). Keep `pdo` in `OTEL_PHP_DISABLED_INSTRUMENTATIONS` unless you need `PDO::connect` or raw PDO calls that bypass the query builder.
- **`clear_env`.** php-fpm's default `clear_env = yes` strips every `OTEL_*` variable from the workers, and nothing gets traced, with no error. The official image sets `clear_env = no` in `docker.conf`. A project's own pool config has to keep it.
- **Queue workers.** `queue:listen` spawns a `queue:work --once` process every ~3 s. Without the sampler rule above, each poll is a 3-second trace with ~20 SQL spans, even on an empty queue. A long-running `queue:work` has the opposite problem: its `Command` root span never ends, so the jobs appear as orphans.
- **Collector down, overlay on** (`dwe stop otel`): requests keep working, but every request writes a 6-line export stack trace to the FPM log. Consider `OTEL_PHP_LOG_DESTINATION`.
- **Variants built with `extends:`** (an xdebug container `extends: {file: docker-compose.yml, service: app}`) read the base file, not this patch, so they are not instrumented. Patching them here breaks the stack while the variant is off (see the "patch only services that exist" trap above).
- **No `python3`** in the official `php:*` images, Debian ones included, so `traces.py` cannot run in the app container. Run it in a throwaway container defined in the same overlay:

```yaml
# compose/otel.yml
  otel-lookup:
    image: python:3.13-alpine
    profiles: ["tools"]          # never started by `compose up`
    volumes:
      - ./workspace/otel:/opt/otel:ro
```

```yaml
# workspace/commands/otel.yml
  traces:
    type: service_run            # compose run --rm; ~0.7 s per call
    service: otel-lookup
    argv: [python3, /opt/otel/traces.py, "${args}"]   # service_run passes --entrypoint "": name the interpreter
```
