<?php
/**
 * Product helpers.
 *
 * @package PluginCity\Harness
 */

namespace PluginCity\Harness;

/**
 * Create a simple product.
 *
 * @param array<string,mixed> $args Optional overrides.
 */
function create_simple_product( array $args = array() ): \WC_Product_Simple {
	$product = new \WC_Product_Simple();
	$product->set_name( $args['name'] ?? 'Harness simple product' );
	$product->set_regular_price( $args['price'] ?? '10' );
	$product->set_status( 'publish' );
	$product->set_catalog_visibility( 'visible' );
	if ( ! empty( $args['virtual'] ) ) {
		$product->set_virtual( true );
	}
	if ( ! empty( $args['downloadable'] ) ) {
		$product->set_downloadable( true );
	}
	$product->save();

	return $product;
}

/**
 * Create a variable product with one attribute and two variations.
 *
 * @param array<string,mixed> $args Optional overrides.
 */
function create_variable_product( array $args = array() ): \WC_Product_Variable {
	$product = new \WC_Product_Variable();
	$product->set_name( $args['name'] ?? 'Harness variable product' );
	$product->set_status( 'publish' );
	$product->save();

	$attribute = new \WC_Product_Attribute();
	$attribute->set_name( 'size' );
	$attribute->set_options( array( 'Small', 'Large' ) );
	$attribute->set_visible( true );
	$attribute->set_variation( true );
	$product->set_attributes( array( $attribute ) );
	$product->save();

	foreach ( array( 'Small' => '12', 'Large' => '15' ) as $size => $price ) {
		$variation = new \WC_Product_Variation();
		$variation->set_parent_id( $product->get_id() );
		$variation->set_attributes( array( 'size' => $size ) );
		$variation->set_regular_price( $price );
		$variation->set_status( 'publish' );
		$variation->save();
	}

	$product->variable_product_sync();
	return wc_get_product( $product->get_id() );
}
