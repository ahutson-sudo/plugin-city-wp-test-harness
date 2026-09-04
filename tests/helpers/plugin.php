<?php
/**
 * Plugin discovery helpers.
 *
 * @package PluginCity\Harness
 */

namespace PluginCity\Harness;

/**
 * Resolve a plugin basename from its slug.
 *
 * @param string $slug Directory slug or file slug.
 */
function plugin_basename_from_slug( string $slug ): string {
	if ( ! function_exists( 'get_plugins' ) ) {
		require_once ABSPATH . 'wp-admin/includes/plugin.php';
	}

	foreach ( get_plugins() as $file => $_data ) {
		if ( $file === $slug . '.php' || dirname( $file ) === $slug ) {
			return $file;
		}
	}

	throw new \RuntimeException( 'Plugin slug not found: ' . $slug );
}

/**
 * Mounted plugin slug from the environment.
 */
function mounted_plugin_slug(): string {
	$slug = (string) getenv( 'PLUGIN_SLUG' );
	if ( '' === $slug ) {
		throw new \RuntimeException( 'PLUGIN_SLUG is not set.' );
	}

	return $slug;
}
