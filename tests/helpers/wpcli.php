<?php
/**
 * Notes for running WP-CLI from plugin tests.
 *
 * Plugin PHP tests already run under `wp eval-file`, so they should call
 * WordPress/WooCommerce APIs directly.
 *
 * From the host or CI, use:
 *
 *   ./scripts/wp.sh plugin list
 *   ./scripts/wp.sh eval 'echo "ok";'
 *
 * @package PluginCity\Harness
 */

namespace PluginCity\Harness;

/**
 * Path to the mounted plugin inside the environment.
 *
 * @param string $slug Plugin slug.
 */
function plugin_container_path( string $slug ): string {
	return '/var/www/html/wp-content/plugins/' . $slug;
}

/**
 * Request a path on the WordPress container without following
 * redirects to localhost (the published host URL).
 *
 * @param string $path URL path, for example /wp-login.php.
 * @return array{error:bool,code:int,message:string}
 */
function internal_http( string $path = '/' ): array {
	$response = wp_remote_get(
		'http://wordpress' . $path,
		array(
			'timeout'     => 15,
			'sslverify'    => false,
			'redirection' => 0,
		)
	);

	if ( is_wp_error( $response ) ) {
		return array(
			'error'   => true,
			'code'    => 0,
			'message' => $response->get_error_message(),
		);
	}

	return array(
		'error'   => false,
		'code'    => (int) wp_remote_retrieve_response_code( $response ),
		'message' => '',
	);
}
