<?php
/**
 * Order helpers.
 *
 * @package PluginCity\Harness
 */

namespace PluginCity\Harness;

/**
 * Create a WooCommerce order with a product and optional customer.
 *
 * @param array<string,mixed> $args {
 *     Optional. product, product_id, customer_id, status, qty.
 * }
 */
function create_order( array $args = array() ): \WC_Order {
	$product = $args['product'] ?? null;
	if ( ! $product instanceof \WC_Product && ! empty( $args['product_id'] ) ) {
		$product = wc_get_product( (int) $args['product_id'] );
	}
	if ( ! $product instanceof \WC_Product ) {
		$product = create_simple_product();
	}

	$order = wc_create_order(
		array(
			'status'      => $args['status'] ?? 'pending',
			'customer_id' => $args['customer_id'] ?? 0,
		)
	);

	if ( is_wp_error( $order ) ) {
		throw new \RuntimeException( $order->get_error_message() );
	}

	$order->add_product( $product, (int) ( $args['qty'] ?? 1 ) );
	$order->set_billing_email( $args['email'] ?? 'buyer@example.test' );
	$order->set_billing_first_name( $args['first_name'] ?? 'Test' );
	$order->set_billing_last_name( $args['last_name'] ?? 'Buyer' );
	$order->calculate_totals();
	$order->save();

	return $order;
}

/**
 * Add a shipping line to an order.
 *
 * @param \WC_Order $order      Order.
 * @param string    $method_id  Method id.
 * @param int       $instance_id Instance id.
 * @param string    $title      Method title.
 */
function add_order_shipping( \WC_Order $order, string $method_id = 'flat_rate', int $instance_id = 0, string $title = 'Flat rate' ): void {
	$item = new \WC_Order_Item_Shipping();
	$item->set_method_id( $method_id );
	$item->set_instance_id( $instance_id );
	$item->set_method_title( $title );
	$order->add_item( $item );
	$order->save();
}
