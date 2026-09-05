<?php
/**
 * Minimal extra-plugin test for harness discovery.
 */

declare(strict_types=1);

$primary = dirname( __DIR__, 2 ) . '/sample-plugin/sample-plugin.php';
if ( ! is_readable( $primary ) ) {
	fwrite( STDERR, "Primary plugin sibling was not mounted at {$primary}\n" );
	exit( 1 );
}

echo "  PASS  extra plugin can see the primary plugin mount" . PHP_EOL;
echo "Results: 1 passed, 0 failed" . PHP_EOL;
exit( 0 );
