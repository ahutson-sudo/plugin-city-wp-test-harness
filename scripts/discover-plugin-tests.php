<?php
/**
 * Print plugin-specific test commands, one per line.
 *
 * Usage: php discover-plugin-tests.php /absolute/plugin/path
 */

declare(strict_types=1);

$plugin = $argv[1] ?? '';
if ( '' === $plugin || ! is_dir( $plugin ) ) {
	fwrite( STDERR, "Plugin path is required and must exist.\n" );
	exit( 1 );
}

$override = getenv( 'PLUGIN_TEST_COMMAND' );
if ( is_string( $override ) && '' !== trim( $override ) ) {
	echo trim( $override ) . PHP_EOL;
	exit( 0 );
}

$harness_script = $plugin . '/tests/run-harness.sh';
if ( is_file( $harness_script ) && is_executable( $harness_script ) ) {
	echo './tests/run-harness.sh' . PHP_EOL;
	exit( 0 );
}

$commands = array();

$composer = $plugin . '/composer.json';
if ( is_file( $composer ) ) {
	$json = json_decode( (string) file_get_contents( $composer ), true );
	$scripts = is_array( $json['scripts'] ?? null ) ? $json['scripts'] : array();
	foreach ( array( 'plugin-city-tests', 'test:wp', 'test:integration', 'test' ) as $key ) {
		if ( empty( $scripts[ $key ] ) ) {
			continue;
		}
		$raw   = $scripts[ $key ];
		$first = is_array( $raw ) ? (string) reset( $raw ) : (string) $raw;
		$first = preg_replace( '/^@php\s+/', 'php ', $first ) ?? $first;
		if ( preg_match( '/^(php|wp|bash|\.\/)/', $first ) ) {
			$commands[] = $first;
			break;
		}
	}
}

$candidates = array(
	'php tests/run-tests.php'            => 'tests/run-tests.php',
	'wp eval-file tests/wp-integration.php' => 'tests/wp-integration.php',
);

foreach ( $candidates as $command => $relative ) {
	if ( ! is_file( $plugin . '/' . $relative ) ) {
		continue;
	}
	$already = false;
	foreach ( $commands as $existing ) {
		if ( str_contains( $existing, $relative ) ) {
			$already = true;
			break;
		}
	}
	if ( ! $already ) {
		$commands[] = $command;
	}
}

if ( is_file( $plugin . '/bin/plugin-city-tests.sh' ) && is_executable( $plugin . '/bin/plugin-city-tests.sh' ) ) {
	$commands[] = './bin/plugin-city-tests.sh';
}

foreach ( array_unique( $commands ) as $command ) {
	echo $command . PHP_EOL;
}
