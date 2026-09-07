<?php
/**
 * Plugin Name: Sample Plugin
 * Description: Fixture plugin used to self-test the Plugin City harness.
 * Version: 1.0.0
 * Requires PHP: 8.1
 */

defined( 'ABSPATH' ) || exit;

// TEMPORARY, DO NOT MERGE. Reproduces the exact bug shape the harness used to
// miss: an always-on admin hook reaching a WooCommerce-only class. Fatal only
// when WooCommerce is inactive, and only once a real admin screen renders.
add_action(
	'admin_notices',
	static function (): void {
		\WC_Admin_Settings::get_option( 'woocommerce_currency' );
	}
);
