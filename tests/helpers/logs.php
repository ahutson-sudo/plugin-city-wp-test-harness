<?php
/**
 * PHP and WordPress error log helpers.
 *
 * @package PluginCity\Harness
 */

namespace PluginCity\Harness;

/**
 * WordPress debug log path.
 */
function debug_log_path(): string {
	return trailingslashit( WP_CONTENT_DIR ) . 'debug.log';
}

/**
 * PHP error log path configured by the harness.
 */
function php_error_log_path(): string {
	return trailingslashit( WP_CONTENT_DIR ) . 'php-error.log';
}

/**
 * Combined log contents.
 */
function error_log_contents(): string {
	$chunks = array();
	foreach ( array( debug_log_path(), php_error_log_path() ) as $path ) {
		if ( is_readable( $path ) ) {
			$chunks[] = (string) file_get_contents( $path );
		}
	}

	return implode( "\n", $chunks );
}

/**
 * Truncate harness log files.
 */
function clear_error_logs(): void {
	foreach ( array( debug_log_path(), php_error_log_path() ) as $path ) {
		if ( file_exists( $path ) ) {
			file_put_contents( $path, '' );
		}
	}
}

/**
 * Whether logs contain a PHP fatal or parse error.
 */
function logs_contain_fatal(): bool {
	return (bool) preg_match( '/PHP (Fatal error|Parse error)/', error_log_contents() );
}

/**
 * Whether logs contain a warning or notice.
 */
function logs_contain_warning(): bool {
	return (bool) preg_match( '/PHP (Warning|Notice|Deprecated)/', error_log_contents() );
}
