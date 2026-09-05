<?php
/**
 * Generic WordPress/WooCommerce/plugin smoke tests.
 *
 * Plugin-specific behaviour does not belong here.
 *
 * @package PluginCity\Harness
 */

require_once dirname( __DIR__ ) . '/helpers/load.php';

use function PluginCity\Harness\add_order_shipping;
use function PluginCity\Harness\assert_same;
use function PluginCity\Harness\assert_true;
use function PluginCity\Harness\clear_error_logs;
use function PluginCity\Harness\create_customer;
use function PluginCity\Harness\create_order;
use function PluginCity\Harness\create_simple_product;
use function PluginCity\Harness\create_variable_product;
use function PluginCity\Harness\ensure_basic_shipping;
use function PluginCity\Harness\error_log_contents;
use function PluginCity\Harness\finish;
use function PluginCity\Harness\hpos_is_enabled;
use function PluginCity\Harness\internal_http;
use function PluginCity\Harness\logs_contain_fatal;
use function PluginCity\Harness\extra_plugin_slug;
use function PluginCity\Harness\mounted_plugin_slug;
use function PluginCity\Harness\plugin_basename_from_slug;
use function PluginCity\Harness\suite;

if ( ! function_exists( 'is_plugin_active' ) ) {
	require_once ABSPATH . 'wp-admin/includes/plugin.php';
}

$slug     = mounted_plugin_slug();
$basename = plugin_basename_from_slug( $slug );
$hpos_mode = (string) getenv( 'HPOS_MODE' );

suite( 'WordPress boots' );
assert_true( is_blog_installed(), 'WordPress is installed' );
assert_true( '' !== get_bloginfo( 'name' ), 'WordPress returns a site name' );
assert_true( false !== get_option( 'siteurl' ), 'siteurl option is readable' );

suite( 'WooCommerce activates' );
assert_true( class_exists( 'WooCommerce' ), 'WooCommerce class is available' );
assert_true( is_plugin_active( 'woocommerce/woocommerce.php' ), 'WooCommerce plugin is active' );
assert_true( function_exists( 'wc_create_order' ), 'WooCommerce order API is available' );

suite( 'Plugin is active' );
assert_true( is_plugin_active( $basename ), $slug . ' is active' );
assert_true( is_dir( WP_PLUGIN_DIR . '/' . $slug ) || file_exists( WP_PLUGIN_DIR . '/' . $basename ), 'Plugin files are mounted' );

$extra_slug = extra_plugin_slug();
if ( '' !== $extra_slug ) {
	$extra_basename = plugin_basename_from_slug( $extra_slug );
	assert_true( is_plugin_active( $extra_basename ), $extra_slug . ' extra plugin is active' );
	assert_true(
		is_dir( WP_PLUGIN_DIR . '/' . $extra_slug ) || file_exists( WP_PLUGIN_DIR . '/' . $extra_basename ),
		'Extra plugin files are mounted'
	);
}

suite( 'HPOS mode' );
if ( 'disabled' === $hpos_mode ) {
	assert_true( ! hpos_is_enabled(), 'HPOS is disabled as requested' );
} else {
	assert_true( hpos_is_enabled(), 'HPOS is enabled as requested' );
}

suite( 'Admin and storefront HTTP' );
clear_error_logs();
$login = internal_http( '/wp-login.php' );
assert_true( ! $login['error'], 'wp-login.php request succeeded' . ( $login['message'] ? ' (' . $login['message'] . ')' : '' ) );
assert_same( 200, $login['code'], 'wp-login.php returns HTTP 200' );

$admin = internal_http( '/wp-admin/' );
assert_true( ! $admin['error'], 'wp-admin request succeeded' );
assert_true( in_array( $admin['code'], array( 200, 301, 302 ), true ), 'wp-admin responds (200 or redirect)' );

$home = internal_http( '/' );
assert_true( ! $home['error'], 'Storefront request succeeded' . ( $home['message'] ? ' (' . $home['message'] . ')' : '' ) );
assert_true( in_array( $home['code'], array( 200, 301, 302 ), true ), 'Storefront responds without a server error' );

suite( 'Bootstrap error log' );
assert_true( ! logs_contain_fatal(), 'No PHP fatal or parse error after HTTP bootstrap' );
$log = error_log_contents();
assert_true( ! str_contains( $log, 'Stack trace' ) || ! logs_contain_fatal(), 'Error log has no fatal stack traces' );

suite( 'WooCommerce order creation' );
$customer_id = create_customer();
assert_true( $customer_id > 0, 'Test customer created' );

$simple = create_simple_product(
	array(
		'name'  => 'Harness catalog item',
		'price' => '9.50',
	)
);
assert_true( $simple->get_id() > 0, 'Simple product created' );

$variable = create_variable_product( array( 'name' => 'Harness variable item' ) );
assert_true( $variable->get_id() > 0, 'Variable product created' );
assert_true( count( $variable->get_children() ) >= 2, 'Variable product has variations' );

$zone_id = ensure_basic_shipping();
assert_true( $zone_id > 0, 'Shipping zone created' );

$order = create_order(
	array(
		'product'     => $simple,
		'customer_id' => $customer_id,
		'status'      => 'processing',
	)
);
add_order_shipping( $order );
$order = wc_get_order( $order->get_id() );

assert_true( $order instanceof WC_Order, 'Order was created' );
assert_true( $order->get_id() > 0, 'Order has an id' );
assert_true( count( $order->get_items() ) > 0, 'Order contains a line item' );
assert_true( (float) $order->get_total() > 0, 'Order total is calculated' );

$reloaded = wc_get_order( $order->get_id() );
assert_true( $reloaded instanceof WC_Order, 'Order is readable through WooCommerce CRUD' );
assert_same( $order->get_id(), $reloaded->get_id(), 'Reloaded order matches the created id' );

finish();
