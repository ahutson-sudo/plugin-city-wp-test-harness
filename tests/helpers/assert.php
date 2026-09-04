<?php
/**
 * Tiny assertion helpers. No PHPUnit required.
 *
 * @package PluginCity\Harness
 */

namespace PluginCity\Harness;

/**
 * @param bool   $condition Pass when true.
 * @param string $message   Assertion label.
 */
function assert_true( bool $condition, string $message ): void {
	if ( $condition ) {
		echo '  PASS  ' . $message . PHP_EOL;
		$GLOBALS['pc_harness_passed'] = ( $GLOBALS['pc_harness_passed'] ?? 0 ) + 1;
		return;
	}

	echo '  FAIL  ' . $message . PHP_EOL;
	$GLOBALS['pc_harness_failed']   = ( $GLOBALS['pc_harness_failed'] ?? 0 ) + 1;
	$GLOBALS['pc_harness_failures'] = $GLOBALS['pc_harness_failures'] ?? array();
	$GLOBALS['pc_harness_failures'][] = $message;
}

/**
 * @param mixed  $expected Expected value.
 * @param mixed  $actual   Actual value.
 * @param string $message  Assertion label.
 */
function assert_same( $expected, $actual, string $message ): void {
	assert_true( $expected === $actual, $message . ' (expected ' . var_export( $expected, true ) . ', got ' . var_export( $actual, true ) . ')' );
}

/**
 * Print a suite header.
 *
 * @param string $name Suite name.
 */
function suite( string $name ): void {
	echo PHP_EOL . $name . PHP_EOL;
}

/**
 * Exit with a failure code if any assertion failed.
 */
function finish(): void {
	$passed = (int) ( $GLOBALS['pc_harness_passed'] ?? 0 );
	$failed = (int) ( $GLOBALS['pc_harness_failed'] ?? 0 );
	echo PHP_EOL . sprintf( 'Results: %d passed, %d failed', $passed, $failed ) . PHP_EOL;

	if ( $failed > 0 ) {
		echo PHP_EOL . 'Failures:' . PHP_EOL;
		foreach ( $GLOBALS['pc_harness_failures'] as $failure ) {
			echo ' - ' . $failure . PHP_EOL;
		}
		exit( 1 );
	}
}
