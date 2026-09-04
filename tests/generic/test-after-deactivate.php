<?php
/**
 * Fresh request after the mounted plugin has been deactivated.
 *
 * @package PluginCity\Harness
 */

require_once dirname( __DIR__ ) . '/helpers/load.php';

use function PluginCity\Harness\assert_true;
use function PluginCity\Harness\finish;
use function PluginCity\Harness\logs_contain_fatal;
use function PluginCity\Harness\mounted_plugin_slug;
use function PluginCity\Harness\plugin_basename_from_slug;
use function PluginCity\Harness\suite;

if ( ! function_exists( 'is_plugin_active' ) ) {
	require_once ABSPATH . 'wp-admin/includes/plugin.php';
}

$slug     = mounted_plugin_slug();
$basename = plugin_basename_from_slug( $slug );

suite( 'Plugin deactivated' );
assert_true( is_blog_installed(), 'WordPress still boots after plugin deactivation' );
assert_true( ! is_plugin_active( $basename ), $slug . ' is inactive' );
assert_true( class_exists( 'WooCommerce' ), 'WooCommerce remains available' );
assert_true( ! logs_contain_fatal(), 'No PHP fatal after plugin deactivation' );

finish();
