<?php
/**
 * Plugin Name: PluginCity screenshot mode
 * Description: Signs a headless browser into wp-admin, strips the furniture, and marks the subject of each shot so it can be cropped exactly. Installed into the harness's disposable WordPress volume by scripts/screenshot.sh.
 *
 * @package PluginCityHarness
 *
 * This file is copied into wp-content/mu-plugins by the screenshot driver with
 * its token substituted. It is deliberately not part of any plugin: it mints
 * an authentication cookie on request, which belongs only inside a throwaway
 * container.
 *
 * Two things here are not obvious and both cost an afternoon.
 *
 * Filtering determine_current_user is not enough. wp-admin/admin.php calls
 * auth_redirect(), which asks wp_validate_auth_cookie() directly and never
 * consults that filter, so every admin screen bounces to wp-login.php. Putting
 * a genuine wp_generate_auth_cookie() value into $_COOKIE does work.
 *
 * It has to happen on plugins_loaded rather than at file scope, because
 * wp-settings.php loads must-use plugins *before* wp_cookie_constants(), so
 * reading LOGGED_IN_COOKIE any earlier is a fatal error on every request.
 */

defined( 'ABSPATH' ) || exit;

const PC_SHOT_TOKEN = 'REPLACE_TOKEN';
const PC_SHOT_USER  = 'admin';

add_action(
	'plugins_loaded',
	static function (): void {
		// phpcs:disable WordPress.Security.NonceVerification.Recommended
		if ( ! isset( $_GET['pc_shot'] ) || ! hash_equals( PC_SHOT_TOKEN, (string) $_GET['pc_shot'] ) ) {
			return;
		}

		$user = get_user_by( 'login', PC_SHOT_USER );

		if ( ! $user ) {
			return;
		}

		$expiry = time() + HOUR_IN_SECONDS;

		$_COOKIE[ LOGGED_IN_COOKIE ] = wp_generate_auth_cookie( $user->ID, $expiry, 'logged_in' );
		$_COOKIE[ AUTH_COOKIE ]      = wp_generate_auth_cookie( $user->ID, $expiry, 'auth' );

		// The cookie lives in $_COOKIE and never reaches the browser, so the
		// heartbeat's auth check comes back logged out and WordPress draws its
		// "session has expired" log-in panel over the middle of the screen.
		add_action(
			'init',
			static function (): void {
				remove_action( 'admin_enqueue_scripts', 'wp_auth_check_load' );
				remove_action( 'wp_enqueue_scripts', 'wp_auth_check_load' );
				remove_action( 'admin_print_footer_scripts', 'wp_auth_check_html', 5 );
			},
			1
		);

		// WordPress and WooCommerce both draw banners across the top of every
		// admin screen, over whatever is being photographed.
		add_action(
			'admin_init',
			static function (): void {
				foreach ( array( 'admin_notices', 'all_admin_notices', 'network_admin_notices', 'user_admin_notices' ) as $hook ) {
					remove_all_actions( $hook );
				}
			},
			99
		);

		add_filter( 'woocommerce_helper_suppress_admin_notices', '__return_true' );
		add_filter( 'show_admin_bar', '__return_false' );

		if ( ! isset( $_GET['pc_chrome'] ) || 'on' !== $_GET['pc_chrome'] ) {
			add_action( 'admin_head', 'pc_shot_strip_furniture', 999 );
			add_action( 'wp_head', 'pc_shot_strip_furniture', 999 );
		}

		$click = isset( $_GET['pc_click'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['pc_click'] ) ) : '';
		$frame = isset( $_GET['pc_frame'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['pc_frame'] ) ) : '';
		$pad   = isset( $_GET['pc_pad'] ) ? absint( $_GET['pc_pad'] ) : 0;
		// phpcs:enable WordPress.Security.NonceVerification.Recommended

		if ( '' === $click && '' === $frame ) {
			return;
		}

		$script = static function () use ( $click, $frame, $pad ): void {
			pc_shot_print_script( $click, $frame, $pad );
		};

		add_action( 'admin_footer', $script, 999 );
		add_action( 'wp_footer', $script, 999 );
	},
	0
);

/**
 * Take the admin menu, the toolbar and the screen tabs off the picture.
 *
 * The published sets in this range are cropped to the plugin's own screen, so
 * the furniture is removed before the photograph rather than cut off after it:
 * cropping a 2x render leaves a visible half-pixel seam where a hidden element
 * leaves none.
 */
function pc_shot_strip_furniture(): void {
	echo '<style id="pc-shot-furniture">
		#adminmenumain, #adminmenuback, #adminmenuwrap, #wpadminbar,
		#wpfooter, #screen-meta, #screen-meta-links, .notice, .update-nag,
		.woocommerce-layout__header, .woocommerce-store-alerts,
		.woocommerce-message { display: none !important; }
		html.wp-toolbar { padding-top: 0 !important; }
		#wpcontent, #wpbody-content { margin-left: 0 !important; padding-left: 0 !important; padding-bottom: 0 !important; }
		#wpbody { padding-top: 0 !important; }
		body.wp-admin { min-width: 0 !important; }
	</style>';
}

/**
 * Open a tab, and draw the rule the cropper looks for.
 *
 * pc_click exists because a tabbed metabox opens on whichever tab its own
 * script picked and a still photograph cannot click. Firing the real click
 * rather than forcing a panel visible with CSS keeps the chosen tab drawn the
 * way its own plugin draws an active one.
 *
 * pc_frame exists because the crop is the part of this job most easily got
 * wrong by hand: a box read off a preview is out by a few pixels, and the
 * error only shows once the set is seen side by side. The page marks its own
 * subject instead, so the numbers come out of the browser's layout.
 *
 * @param string $click    Selector to click first, or ''.
 * @param string $frame    Selector list whose union is the subject, or ''.
 * @param int    $pad      Pixels of page to keep around the subject.
 */
function pc_shot_print_script( string $click, string $frame, int $pad ): void {
	printf(
		'<script>window.addEventListener("load",function(){
			var click=%1$s, frame=%2$s, pad=%3$d;
			if(click){var c=document.querySelector(click); if(c){c.click();}}
			if(!frame){return;}
			setTimeout(function(){
				/* The union of every match, not the first: wp-admin lays its
				   columns out with floats, so the wrapper that looks like the
				   subject measures a few pixels high and a frame round it
				   photographs a strip of nothing. */
				var all=[].slice.call(document.querySelectorAll(frame)).map(function(n){
					return n.getBoundingClientRect();
				}).filter(function(b){ return b.width>1 && b.height>1; });
				if(!all.length){return;}
				var left=Math.min.apply(null, all.map(function(b){return b.left;}));
				var top=Math.min.apply(null, all.map(function(b){return b.top;}));
				var right=Math.max.apply(null, all.map(function(b){return b.right;}));
				var bottom=Math.max.apply(null, all.map(function(b){return b.bottom;}));
				/* The rule is drawn inside the frame rather than round it, and
				   the frame is clamped to the page. A subject flush against the
				   top of the document has no room for a rule above it, and an
				   outside rule there is simply not photographed -- which the
				   cropper cannot tell from a frame that was never drawn. */
				var L=Math.max(0, left+window.scrollX-pad);
				var T=Math.max(0, top+window.scrollY-pad);
				var d=document.createElement("div");
				d.id="pc-shot-frame";
				d.style.cssText="position:absolute;z-index:2147483647;pointer-events:none;"
					+"box-sizing:border-box;background:transparent;"
					+"box-shadow:inset 0 0 0 2px #ff00ff;"
					+"left:"+L+"px;top:"+T+"px;"
					+"width:"+(right+window.scrollX+pad-L)+"px;"
					+"height:"+(bottom+window.scrollY+pad-T)+"px;";
				document.body.appendChild(d);
			},350);
		});</script>',
		wp_json_encode( $click ),
		wp_json_encode( $frame ),
		$pad
	);
}
