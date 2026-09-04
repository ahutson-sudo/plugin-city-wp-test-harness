<?php
/**
 * Shipping helpers.
 *
 * @package PluginCity\Harness
 */

namespace PluginCity\Harness;

/**
 * Enable shipping and add a simple zone with flat rate and local pickup.
 *
 * @return int Zone id.
 */
function ensure_basic_shipping(): int {
	update_option( 'woocommerce_ship_to_countries', 'all' );
	update_option( 'woocommerce_shipping_cost_requires_address', 'no' );

	if ( ! class_exists( '\WC_Shipping_Zones' ) ) {
		throw new \RuntimeException( 'WooCommerce shipping is not available.' );
	}

	$zones = \WC_Shipping_Zones::get_zones();
	foreach ( $zones as $zone_data ) {
		if ( 'Harness zone' === ( $zone_data['zone_name'] ?? '' ) ) {
			return (int) $zone_data['id'];
		}
	}

	$zone = new \WC_Shipping_Zone();
	$zone->set_zone_name( 'Harness zone' );
	$zone->set_zone_order( 0 );
	$zone->save();
	$zone->add_location( 'GB', 'country' );
	$zone->add_shipping_method( 'flat_rate' );
	$zone->add_shipping_method( 'local_pickup' );

	return $zone->get_id();
}

/**
 * Set a shipping method instance to a custom cost.
 *
 * @param int    $instance_id Method instance.
 * @param string $cost        Cost string.
 */
function set_shipping_method_cost( int $instance_id, string $cost ): void {
	$settings = get_option( 'woocommerce_flat_rate_' . $instance_id . '_settings', array() );
	if ( ! is_array( $settings ) ) {
		$settings = array();
	}
	$settings['cost'] = $cost;
	update_option( 'woocommerce_flat_rate_' . $instance_id . '_settings', $settings );
}
