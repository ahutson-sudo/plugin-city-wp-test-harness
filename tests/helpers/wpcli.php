<?php
/**
 * Notes for running WP-CLI from plugin tests.
 *
 * Plugin PHP tests already run under `wp eval-file`, so they should call
 * WordPress/WooCommerce APIs directly.
 *
 * From the host or CI, use:
 *
 *   ./scripts/wp.sh plugin list
 *   ./scripts/wp.sh eval 'echo "ok";'
 *
 * @package PluginCity\Harness
 */

namespace PluginCity\Harness;

/**
 * Path to the mounted plugin inside the environment.
 *
 * @param string $slug Plugin slug.
 */
function plugin_container_path( string $slug ): string {
	return '/var/www/html/wp-content/plugins/' . $slug;
}
