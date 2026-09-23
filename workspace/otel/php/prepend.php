<?php

// auto_prepend_file for app-main while the otel tool is enabled (zz-otel.ini,
// mounted by compose/tools/otel-apps.yml). Loads the OTel SDK from the sidecar
// vendor dir WITHOUT touching the app's composer.json.
//
// Order matters: the app's own autoloader is required FIRST. The sidecar vendor
// holds only OTel-only packages (see ensure.sh), so the SDK's bootstrap files
// need the app's copies of psr/*, guzzle, symfony/polyfill-* to be loadable
// already. Requiring the app's autoload.php twice is safe: Composer's
// getLoader() returns the cached loader on the second call (public/index.php).
//
// Scope: php-fpm requests and `php artisan` only. Every other PHP process in
// the container (composer itself, phpunit, one-off `php -r`) inherits the same
// ini and must stay untouched — loading the app's vendor into composer's own
// process would mix two Symfony Console versions.

(static function (): void {
    $sapi = PHP_SAPI;
    $script = (string) ($_SERVER['SCRIPT_FILENAME'] ?? '');
    if ($sapi !== 'fpm-fcgi' && !($sapi === 'cli' && basename($script) === 'artisan')) {
        return;
    }
    if (!extension_loaded('opentelemetry')) {
        return;
    }
    $app = getenv('OTEL_PHP_APP_AUTOLOAD') ?: '/workspace/src/vendor/autoload.php';
    $otel = __DIR__ . '/build/vendor/autoload.php';
    if (!is_file($app) || !is_file($otel)) {
        return;
    }
    // Queue workers: `queue:listen` (the services.main.queue daemon) re-spawns
    // `artisan queue:work --once` every few seconds, and each poll would be a
    // trace of its own with ~20 SQL spans even when the queue is empty. Drop
    // every ROOT span in worker processes but keep spans with a remote parent:
    // Laravel carries the dispatcher's traceparent in the job payload, so a
    // processed job still shows up inside the trace of the request (or command)
    // that dispatched it.
    $cmd = (string) ($_SERVER['argv'][1] ?? '');
    if ($sapi === 'cli' && in_array($cmd, ['queue:work', 'queue:listen'], true) && getenv('OTEL_TRACES_SAMPLER') === false) {
        putenv('OTEL_TRACES_SAMPLER=parentbased_always_off');
    }
    require $app;
    require $otel;
})();
