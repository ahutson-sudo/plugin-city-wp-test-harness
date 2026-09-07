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
 * @param string              $path URL path, for example /wp-login.php.
 * @param array<string,mixed> $args Extra wp_remote_get arguments.
 * @return array{error:bool,code:int,message:string,body:string}
 */
function internal_http( string $path = '/', array $args = array() ): array {
	$response = wp_remote_get(
		'http://wordpress' . $path,
		array_merge(
			array(
				'timeout'     => 15,
				'sslverify'   => false,
				'redirection' => 0,
			),
			$args
		)
	);

	if ( is_wp_error( $response ) ) {
		return array(
			'error'   => true,
			'code'    => 0,
			'message' => $response->get_error_message(),
			'body'    => '',
		);
	}

	return array(
		'error'   => false,
		'code'    => (int) wp_remote_retrieve_response_code( $response ),
		'message' => '',
		'body'    => (string) wp_remote_retrieve_body( $response ),
	);
}

/**
 * The first administrator on the site.
 */
function administrator_id(): int {
	$admins = get_users(
		array(
			'role'    => 'administrator',
			'number'  => 1,
			'orderby' => 'ID',
			'fields'  => 'ID',
		)
	);

	return array() === $admins ? 0 : (int) $admins[0];
}

/**
 * Request an admin page as a signed-in administrator.
 *
 * An anonymous /wp-admin/ request only ever redirects to the login form, so it
 * proves the redirect works and nothing else: no admin screen is built, and
 * admin_notices, admin_init and admin_post_* never run. Anything a plugin hangs
 * on those hooks stays invisible until a real admin page renders for a real
 * user, which is what this does.
 *
 * @param string $path Admin path, for example /wp-admin/plugins.php.
 * @return array{error:bool,code:int,message:string,body:string}
 */
function admin_http( string $path = '/wp-admin/' ): array {
	$user_id = administrator_id();

	if ( $user_id < 1 ) {
		return array(
			'error'   => true,
			'code'    => 0,
			'message' => 'no administrator account to sign in as',
			'body'    => '',
		);
	}

	$expiration = time() + HOUR_IN_SECONDS;

	// A cookie without a real session token fails wp_validate_auth_cookie, so
	// mint a session the way wp_set_auth_cookie does and sign both cookies with
	// the same token.
	$token   = \WP_Session_Tokens::get_instance( $user_id )->create( $expiration );
	$cookies = array();

	foreach ( array( 'AUTH_COOKIE' => 'auth', 'LOGGED_IN_COOKIE' => 'logged_in' ) as $constant => $scheme ) {
		if ( defined( $constant ) ) {
			$cookies[] = constant( $constant ) . '=' . wp_generate_auth_cookie( $user_id, $expiration, $scheme, $token );
		}
	}

	if ( array() === $cookies ) {
		return array(
			'error'   => true,
			'code'    => 0,
			'message' => 'WordPress cookie constants are not defined',
			'body'    => '',
		);
	}

	return internal_http( $path, array( 'headers' => array( 'Cookie' => implode( '; ', $cookies ) ) ) );
}

/**
 * Whether a response is a rendered admin screen rather than a login redirect.
 *
 * @param array{error:bool,code:int,message:string,body:string} $response Response.
 */
function is_admin_screen( array $response ): bool {
	if ( $response['error'] || 200 !== $response['code'] ) {
		return false;
	}

	return str_contains( $response['body'], 'id="adminmenu"' )
		|| str_contains( $response['body'], 'id="wpadminbar"' );
}
