<?php
/**
 * Customer helpers.
 *
 * @package PluginCity\Harness
 */

namespace PluginCity\Harness;

/**
 * Create a test customer.
 *
 * @param array<string,mixed> $args Optional overrides.
 *
 * @return int User id.
 */
function create_customer( array $args = array() ): int {
	$email = $args['email'] ?? ( 'customer-' . wp_generate_password( 8, false ) . '@example.test' );

	$existing = get_user_by( 'email', $email );
	if ( $existing ) {
		return (int) $existing->ID;
	}

	$user_id = wc_create_new_customer(
		$email,
		$args['username'] ?? sanitize_user( current( explode( '@', $email ) ) ),
		$args['password'] ?? 'password'
	);

	if ( is_wp_error( $user_id ) ) {
		throw new \RuntimeException( $user_id->get_error_message() );
	}

	return (int) $user_id;
}
