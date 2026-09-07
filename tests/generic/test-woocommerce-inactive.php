<?php
/**
 * Fresh request after WooCommerce has been deactivated.
 *
 * @package PluginCity\Harness
 */

require_once dirname( __DIR__ ) . '/helpers/load.php';

use function PluginCity\Harness\admin_http;
use function PluginCity\Harness\assert_true;
use function PluginCity\Harness\clear_error_logs;
use function PluginCity\Harness\error_log_contents;
use function PluginCity\Harness\extra_plugin_slug;
use function PluginCity\Harness\finish;
use function PluginCity\Harness\internal_http;
use function PluginCity\Harness\is_admin_screen;
use function PluginCity\Harness\logs_contain_fatal;
use function PluginCity\Harness\mounted_plugin_slug;
use function PluginCity\Harness\plugin_basename_from_slug;
use function PluginCity\Harness\suite;

if ( ! function_exists( 'is_plugin_active' ) ) {
	require_once ABSPATH . 'wp-admin/includes/plugin.php';
}

$slug     = mounted_plugin_slug();
$basename = plugin_basename_from_slug( $slug );

suite( 'WooCommerce inactive' );
assert_true( is_blog_installed(), 'WordPress boots with WooCommerce inactive' );
assert_true( ! class_exists( 'WooCommerce', false ), 'WooCommerce class is not loaded' );
assert_true( ! is_plugin_active( 'woocommerce/woocommerce.php' ), 'WooCommerce plugin is inactive' );
assert_true( ! logs_contain_fatal(), 'Mounted plugin does not fatal when WooCommerce is inactive' );

// Everything below is only worth anything if the plugin is still switched on.
// WordPress leaves a dependent plugin active when its dependency is
// deactivated, so this should hold; if it ever stops holding, the rest of this
// suite is passing vacuously and we want to be told rather than reassured.
$still_active = is_plugin_active( $basename );
assert_true( $still_active, $slug . ' is still active while WooCommerce is inactive' );

$home = internal_http( '/' );
assert_true( ! $home['error'], 'Storefront request works with WooCommerce inactive' );
assert_true( in_array( $home['code'], array( 200, 301, 302 ), true ), 'Storefront does not 500 with WooCommerce inactive' );
assert_true( ! logs_contain_fatal(), 'No PHP fatal after storefront request with WooCommerce inactive' );

// The storefront never runs admin_notices, admin_init or admin_post_*, so a
// plugin can reach for a WooCommerce-only class on one of those hooks and look
// perfectly healthy here. Sign in and render real admin screens instead.
suite( 'wp-admin with WooCommerce inactive' );
clear_error_logs();

$screens = array(
	'/wp-admin/'                    => 'Dashboard',
	'/wp-admin/plugins.php'         => 'Plugins screen',
	'/wp-admin/options-general.php' => 'Settings screen',
);

foreach ( $screens as $path => $label ) {
	$response = admin_http( $path );
	$detail   = '' !== $response['message'] ? ' (' . $response['message'] . ')' : ' (HTTP ' . $response['code'] . ')';

	assert_true( ! $response['error'], $label . ' request succeeded with WooCommerce inactive' . $detail );
	assert_true( is_admin_screen( $response ), $label . ' renders for a signed-in admin with WooCommerce inactive' . $detail );
	assert_true( ! logs_contain_fatal(), 'No PHP fatal after the ' . strtolower( $label ) . ' with WooCommerce inactive' );
}

$log = error_log_contents();
assert_true( ! str_contains( $log, 'Stack trace' ), 'No stack traces logged from wp-admin with WooCommerce inactive' );

$extra = extra_plugin_slug();
if ( '' !== $extra ) {
	assert_true(
		is_plugin_active( plugin_basename_from_slug( $extra ) ),
		$extra . ' add-on is still active while WooCommerce is inactive'
	);
}

finish();
