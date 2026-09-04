<?php
/**
 * High-Performance Order Storage helpers.
 *
 * @package PluginCity\Harness
 */

namespace PluginCity\Harness;

/**
 * Enable HPOS using WooCommerce options.
 */
function enable_hpos(): void {
	update_option( 'woocommerce_custom_orders_table_enabled', 'yes' );
	update_option( 'woocommerce_custom_orders_table_data_sync_enabled', 'yes' );
	update_option( 'woocommerce_feature_custom_order_tables_enabled', 'yes' );
}

/**
 * Disable HPOS using WooCommerce options.
 */
function disable_hpos(): void {
	update_option( 'woocommerce_custom_orders_table_enabled', 'no' );
	update_option( 'woocommerce_custom_orders_table_data_sync_enabled', 'no' );
	update_option( 'woocommerce_feature_custom_order_tables_enabled', 'no' );
}

/**
 * Whether HPOS is currently in use.
 */
function hpos_is_enabled(): bool {
	if ( class_exists( \Automattic\WooCommerce\Utilities\OrderUtil::class ) ) {
		return \Automattic\WooCommerce\Utilities\OrderUtil::custom_orders_table_usage_is_enabled();
	}

	return 'yes' === get_option( 'woocommerce_custom_orders_table_enabled' );
}

/**
 * Apply HPOS_MODE from the environment.
 */
function apply_hpos_mode( ?string $mode = null ): void {
	$mode = $mode ?? (string) getenv( 'HPOS_MODE' );
	if ( 'disabled' === $mode ) {
		disable_hpos();
		return;
	}

	enable_hpos();
}
