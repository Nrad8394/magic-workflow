<?php
// Debug: use Nextcloud's OWN HTTP client to fetch the Keycloak discovery doc,
// exactly as user_oidc does. Prints the real error. Run inside nextcloud-app.
require_once '/var/www/html/lib/base.php';
$url = $argv[1] ?? 'https://id.magic.test/realms/magicworkflow/.well-known/openid-configuration';
try {
    $cs = \OC::$server->get(\OCP\Http\Client\IClientService::class);
    $r = $cs->newClient()->get($url);
    echo "OK http=" . $r->getStatusCode() . " bytes=" . strlen((string)$r->getBody()) . "\n";
} catch (\Throwable $e) {
    echo "FAIL: " . get_class($e) . ": " . $e->getMessage() . "\n";
}
