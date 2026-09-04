<?php
/**
 * Fresh request after WooCommerce has been deactivated.
 *
 * @package PluginCity\Harness
 */

require_once dirname( __DIR__ ) . '/helpers/load.php';

use function PluginCity\Harness\assert_true;
use function PluginCity\Harness\finish;
use function PluginCity\Harness\internal_http;
use function PluginCity\Harness\logs_contain_fatal;
use function PluginCity\Harness\suite;

if ( ! function_exists( 'is_plugin_active' ) ) {
	require_once ABSPATH . 'wp-admin/includes/plugin.php';
}

suite( 'WooCommerce inactive' );
assert_true( is_blog_installed(), 'WordPress boots with WooCommerce inactive' );
assert_true( ! class_exists( 'WooCommerce', false ), 'WooCommerce class is not loaded' );
assert_true( ! is_plugin_active( 'woocommerce/woocommerce.php' ), 'WooCommerce plugin is inactive' );
assert_true( ! logs_contain_fatal(), 'Mounted plugin does not fatal when WooCommerce is inactive' );

$home = internal_http( '/' );
assert_true( ! $home['error'], 'Storefront request works with WooCommerce inactive' );
assert_true( in_array( $home['code'], array( 200, 301, 302 ), true ), 'Storefront does not 500 with WooCommerce inactive' );
assert_true( ! logs_contain_fatal(), 'No PHP fatal after storefront request with WooCommerce inactive' );

finish();
