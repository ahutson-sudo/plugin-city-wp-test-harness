<?php
/**
 * The part of a screenshot seed that is the same whatever the plugin is.
 *
 * A seed script builds a believable shop for scripts/screenshot.sh to
 * photograph. Most of one is the product's own: its catalogue, its settings,
 * and whatever state its captions need. What is left over is currency, locale,
 * two WooCommerce switches and a mail short-circuit, and that part had been
 * retyped from memory twice and got wrong both times.
 *
 * Two calls, one at each end of a seed:
 *
 *     require_once getenv( 'PC_HARNESS_ROOT' ) . '/tests/helpers/seed-common.php';
 *
 *     PluginCity\Harness\seed_us_shop( array( 'name' => 'Thornbury Books' ) );
 *     // ... the plugin's own catalogue, settings and state ...
 *     PluginCity\Harness\seed_record_id( 'product', $slug, $id );
 *     PluginCity\Harness\seed_finish();
 *
 * The bookend shape is deliberate. Caches have to be dropped after the last
 * write rather than after the shared ones, and the file of ids cannot be
 * written until everything that has an id exists, so both of those belong at
 * the end and neither can live in the opening call.
 *
 * @package PluginCity\Harness
 */

namespace PluginCity\Harness;

/**
 * Where the ids a seed created are written for the screenshot driver to read.
 *
 * Inside the WordPress volume, so it is thrown away with the shop it describes
 * -- ids from a previous shop are worse than none. scripts/screenshot.sh reads
 * this same path out of the container; the two are written down separately and
 * each names the other.
 */
const SEED_IDS_FILE = '/var/www/html/pc-seed-ids.json';

/**
 * Ids recorded so far, as kind => key => id.
 *
 * Seeded from the file if one is already there, because a product photographed
 * in two editions wants its shop built by one seed and the paid extras added by
 * a second, and wp-cli runs each of those in a process of its own. Starting
 * empty, the second seed_finish() wrote a file holding only what the second seed
 * had made and every placeholder naming the shop stopped resolving -- a failure
 * that reads as a shot list typo rather than as the file having been truncated.
 *
 * @var array<string,array<string,int>>
 */
$GLOBALS['pc_seed_ids'] = array();

if ( is_readable( SEED_IDS_FILE ) ) {
	$pc_seed_existing = json_decode( (string) file_get_contents( SEED_IDS_FILE ), true );

	if ( is_array( $pc_seed_existing ) ) {
		$GLOBALS['pc_seed_ids'] = $pc_seed_existing;
	}

	unset( $pc_seed_existing );
}

/**
 * Make the shop a United States shop, in dollars, with US dates.
 *
 * Everything here is a house rule rather than a judgement a product gets to
 * make: the range is sold in dollars and photographed in US date order, so a
 * set that comes back reading "10 November 2026" is wrong however good the
 * picture is.
 *
 * Overrides are a single array of named keys, not parameters, because each of
 * the nine seeds wants a different two or three of them. Positional arguments
 * would have every seed restating defaults it does not care about, and the day
 * a tenth setting is added they would all have to be edited. A bookshop and a
 * hardware shop differ by their name and their town and nothing else in here.
 *
 * @param array<string,mixed> $shop Optional: name, description, timezone,
 *                                  address, address_2, city, postcode, country,
 *                                  date_format. The state goes in `country` as
 *                                  WooCommerce stores it, `US:NC`; a `state` key
 *                                  was documented here and read by nothing, so a
 *                                  shop that passed one was quietly put in Oregon.
 */
function seed_us_shop( array $shop = array() ): void {
	// There is no mail server behind the container, so every order email fails
	// and WooCommerce writes the failure into the order notes -- which are then
	// the most prominent thing on the order screen being photographed, and they
	// describe the harness rather than the shop. Short-circuiting wp_mail() is
	// cheaper than reading a rejected screenshot and wondering what went wrong.
	add_filter( 'pre_wp_mail', '__return_true' );

	update_option( 'blogname', $shop['name'] ?? 'Harness Shop' );
	update_option( 'blogdescription', $shop['description'] ?? '' );

	// The harness installs a timezone of its own for tests (WP_TIMEZONE in
	// .env). A seed sets its own anyway: the shop being photographed is in a
	// town, and it is the seed that knows which one.
	update_option( 'timezone_string', $shop['timezone'] ?? 'America/New_York' );
	update_option( 'gmt_offset', '' );
	update_option( 'date_format', $shop['date_format'] ?? 'F j, Y' );
	update_option( 'time_format', 'g:i a' );
	update_option( 'start_of_week', 0 );

	// Set explicitly rather than left to the default: a shop that has never
	// been through the WooCommerce wizard has no currency of its own, and the
	// default is not ours.
	update_option( 'woocommerce_currency', 'USD' );
	update_option( 'woocommerce_currency_pos', 'left' );
	update_option( 'woocommerce_price_decimal_sep', '.' );
	update_option( 'woocommerce_price_thousand_sep', ',' );
	update_option( 'woocommerce_price_num_decimals', 2 );

	update_option( 'woocommerce_store_address', $shop['address'] ?? '1408 NE Alberta St' );
	update_option( 'woocommerce_store_address_2', $shop['address_2'] ?? '' );
	update_option( 'woocommerce_store_city', $shop['city'] ?? 'Portland' );
	update_option( 'woocommerce_default_country', $shop['country'] ?? 'US:OR' );
	update_option( 'woocommerce_store_postcode', $shop['postcode'] ?? '97211' );

	// Taxes and reviews are off because both put something on the photograph
	// that the plugin did not put there: a tax line under every price, and a
	// reviews tab on every product page.
	update_option( 'woocommerce_calc_taxes', 'no' );
	update_option( 'woocommerce_enable_reviews', 'no' );

	seed_open_the_storefront();
	seed_tidy_the_front_of_the_site();
}

/**
 * Take the shop out from behind the Coming soon page.
 *
 * WooCommerce 11 puts a new store behind one, and the way it fails is the
 * problem: every storefront URL answers 200 with a
 * `wp-block-woocommerce-coming-soon` page, so a capture succeeds, writes a
 * file, and the file is a picture of a holding page. Nothing is logged and no
 * request errors, which is twenty minutes gone before anybody thinks to read
 * the HTML they photographed.
 *
 * Both options are needed. `woocommerce_coming_soon` is the switch; with
 * `woocommerce_store_pages_only` left at `yes` the shop and product pages stay
 * behind it while the rest of the site comes out, which looks like the first
 * setting not having worked.
 */
function seed_open_the_storefront(): void {
	update_option( 'woocommerce_coming_soon', 'no' );
	update_option( 'woocommerce_store_pages_only', 'no' );

	// Not the storefront, but the same shape of failure and the same one line to
	// fix it. WooCommerce sends the first wp-admin request after it is activated
	// to its own setup wizard, and on a fresh shop the first wp-admin request
	// anybody makes is the camera's: the screen it was pointed at answers 302,
	// nothing is framed, and the only thing said out loud is that no frame was
	// found -- which reads as a wrong selector.
	delete_transient( '_wc_activation_redirect' );
	delete_option( '_wc_activation_redirect' );
}

/**
 * Make the front of the site look like a shop rather than a fresh install.
 *
 * A block theme's home page is a blog roll, and a new install has a Sample Page
 * in the menu. Neither belongs in a photograph of a shop, and both are outside
 * what any plugin is responsible for.
 */
function seed_tidy_the_front_of_the_site(): void {
	$shop_page = function_exists( 'wc_get_page_id' ) ? wc_get_page_id( 'shop' ) : 0;

	if ( $shop_page > 0 ) {
		update_option( 'show_on_front', 'page' );
		update_option( 'page_on_front', $shop_page );
	}

	foreach ( array( 'sample-page', 'refund_returns' ) as $slug ) {
		$page = get_page_by_path( $slug );
		if ( $page ) {
			wp_delete_post( $page->ID, true );
		}
	}
}

/**
 * Start a basket as the customer whose storefront is going to be photographed.
 *
 * The opening half of a pair; seed_hand_the_cart_to() is the closing half.
 *
 *     seed_start_a_cart_for( $customer_id );
 *     WC()->cart->add_to_cart( $product_id, 2 );
 *     WC()->cart->calculate_totals();
 *     WC()->session->set( 'chosen_shipping_methods', array( 'flat_rate:3' ) );
 *     seed_hand_the_cart_to( $customer_id );
 *
 * `wc_load_cart()` on its own is not enough, and the reason is that it does not
 * necessarily load anything: `initialize_session()` and `initialize_cart()` each
 * build only when there is nothing there already, so a second call hands back
 * whatever the process is still holding. A seed that photographs two customers
 * therefore fills one basket, hands it over, fills "another" -- and the second
 * customer's row is written from the first customer's session.
 *
 * Which customer a session belongs to is decided once, when the session object
 * is built, by asking who is signed in at that moment. Signing in afterwards is
 * too late, and nothing complains: WooCommerce simply mints a guest token
 * instead, and the row goes somewhere no browser will look. So the sign-in has
 * to come first and the session has to be thrown away, which is what this does.
 *
 * The basket arrives **empty**, however full the one stored against that account
 * is, because it is emptied here in memory. Usually that is what a seed wants.
 * When it is not -- a second seed script adjusting a shop the first one already
 * filled -- ask for the stored one outright:
 *
 *     seed_start_a_cart_for( $customer_id );
 *     WC()->cart->get_cart_from_session();
 *     WC()->cart->calculate_totals();
 *
 * Leave that out and the re-run reads an empty basket, finds no delivery rates
 * in it, and writes the empty basket over the full one -- which is worse than
 * not having run at all.
 *
 * @param int $user_id The customer the storefront shots are taken as.
 */
function seed_start_a_cart_for( int $user_id ): void {
	wp_set_current_user( $user_id );

	/*
	 * The session and the customer are thrown away, because both answered for
	 * whoever the process was before. The cart is deliberately **not**, and this
	 * is the one line here worth reading twice.
	 *
	 * `WC_Cart_Session::init()` hooks `set_session()` on
	 * `woocommerce_after_calculate_totals` when a cart is built, and nothing
	 * unhooks it when that cart is discarded. So a second cart does not replace
	 * the first one's callback, it joins it -- and the abandoned one still wraps
	 * a cart with nothing in it. `set_session()` nulls
	 * `chosen_shipping_methods`, `previous_shipping_methods` and
	 * `shipping_method_counts` whenever the cart it holds has nothing shippable,
	 * so the next `calculate_totals()` wipes the chosen delivery method no matter
	 * which cart did the work.
	 *
	 * Measured, on one shop with one variable: discarding the cart leaves the
	 * session with no chosen method at all after the totals; keeping it leaves
	 * the pinned rate in place. A cart already exists by the time a WP-CLI script
	 * runs, so the discard was never the harmless-looking half of this.
	 */
	WC()->session  = null;
	WC()->customer = null;

	wc_load_cart();

	// Whatever the process was holding belongs to the customer before this one.
	// Cleared in memory rather than through empty_cart(), which would also delete
	// the basket WooCommerce has stored against the account.
	WC()->cart->set_cart_contents( array() );
	WC()->cart->set_removed_cart_contents( array() );
	WC()->cart->set_applied_coupons( array() );
}

/**
 * Give the cart a seed has just built to the customer who will be photographed.
 *
 * Call this after the cart is filled and the totals are worked out, with the id
 * of the customer whose storefront the shots are taken as. It also settles the
 * delivery method, which is the part of a cart that does not look after itself:
 * see seed_settle_the_delivery_method(), which it calls for you.
 *
 * Without it the browser finds a different cart from the one the seed built,
 * and nothing anywhere says so. `wc_load_cart()` under WP-CLI mints a guest
 * session token rather than reading the user the seed signed in as, so
 * everything written through the session handler lands under a key that
 * customer's browser will never look at.
 *
 * What makes that expensive rather than obvious is that the basket survives
 * anyway: WooCommerce also keeps a persistent copy against the account and
 * restores it at sign-in, so the products, the quantities and the totals are
 * all correct in the picture. Only what lives *solely* in the session is gone,
 * and the chosen shipping method is the one that matters -- WooCommerce picks
 * again, and a shot whose subject depends on the method photographs a page that
 * drew perfectly and has nothing on it.
 *
 * What it picks is not the cheapest rate, which is the guess to get out of the
 * way first, because a shot that is wrong for this reason usually looks right and
 * the cheapest-rate guess is why. `wc_get_default_shipping_method_for_package()`
 * takes **the first rate the zone offers** -- that is, the order the methods were
 * added to it. Collection is skipped in that walk only when the cart says it was
 * built by a page WooCommerce recognises; a cart a seed built reports its context
 * as `shortcode`, and on that branch the literal first rate is taken, collection
 * included. Both are the zone's own order, so a seed that adds free shipping
 * before its flat rate gets free shipping in the picture whatever it asked for,
 * and gets it for the basket that qualifies and not for the one that does not,
 * which is indistinguishable from the seed having worked. Reorder the two lines
 * that build the zone and the same shot list charges postage under a bar
 * announcing free delivery.
 *
 * It is also what makes such a shot reproduce. Left to WooCommerce the method
 * depends on the order the zone was built in, and a row written by an earlier run
 * is read in preference to anything this one did, so a set can come back
 * identical twice and still be of a state the seed never asked for.
 *
 * Nor does it stay wrong in the same way, because what the row names is
 * renumbered. A chosen method is stored as a kind and an instance --
 * `flat_rate:7` -- and the instance id is minted when the method is added to a
 * zone, so a shop rebuilt from empty gives the same van a different number.
 * While the numbers still match, every run agrees with the first and all of
 * them are wrong together; once the zones are rebuilt the row names a rate that
 * no longer exists, WooCommerce chooses for itself again, and the same shot list
 * photographs something else with nothing in the code having changed. That is
 * what turns a reliably wrong picture into an occasionally wrong one, and the
 * occasional one is what survives being looked at. So a reproduction check only
 * means anything from an empty shop: re-run against the shop already there, it
 * compares the leftover row with itself.
 *
 * One thing this cannot do for you, because by the time it runs the evidence is
 * gone: **pin the method where the totals will agree with it.** Totals do not
 * leave a chosen method alone -- they ask
 * `wc_get_chosen_shipping_method_for_package()` for each package, which keeps a
 * stored choice only when four things hold at once: something is stored, the rate
 * is still on offer, `previous_shipping_methods` names the same rates the package
 * now has, and `shipping_method_counts` agrees on how many. The last two are the
 * ones a seed has to earn, because a session that has never served a page load
 * has neither, and without them the choice reads as a shop that changed under the
 * customer.
 *
 * Two shapes earn it, and both are in use:
 *
 *   - Pin **after** the last `calculate_totals()`. Nothing asks again, so nothing
 *     can disagree. This is the simplest to reason about.
 *   - Pin after a `calculate_shipping()` and before the totals. That call is what
 *     writes both bookkeeping keys from the rates as they now stand, so the
 *     totals find a choice that matches and leave it alone. Measured on two
 *     products' seeds: the pinned rate is still there afterwards, and it is the
 *     rate the next process reads.
 *
 * What does not survive is a pin written into a session where no rates have been
 * worked out at all. Nor does one written while a **discarded cart** is still
 * hooked -- see seed_start_a_cart_for(), where that is explained, because it is
 * the cart rather than the ordering that does the damage and it was mistaken for
 * the ordering once already.
 *
 * A lost pin leaves a session indistinguishable from one the seed never pinned,
 * so nothing can tell those two apart afterwards, this function included. It
 * reports the method the photograph is going to use and whether anything is
 * holding it there, which is the only honest thing available. Read that line.
 *
 * @param int $user_id The customer the storefront shots are taken as.
 */
function seed_hand_the_cart_to( int $user_id ): void {
	global $wpdb;

	if ( ! function_exists( 'WC' ) || ! WC()->session || ! WC()->cart ) {
		fwrite( STDERR, "No cart to hand over: call wc_load_cart() and fill it first.\n" );

		return;
	}

	/*
	 * Whose session this is, as opposed to whose it is about to be filed under.
	 * The answer was settled when the session object was built, by asking who was
	 * signed in at that moment.
	 *
	 * A guest token is **not** a fault, and saying so was one. It is what
	 * `wc_load_cart()` mints under WP-CLI whoever is signed in, so it is what a
	 * seed with one customer in it has; the row this function then writes under
	 * that customer's own id is the repair, and the guest row is simply never
	 * read. Two working seeds were accused of the defect this check exists to
	 * find, which is worse than not checking, because the next person fixes the
	 * seed.
	 *
	 * A different *named* customer is a real fault: it means an earlier customer
	 * was handed a cart in this same process and the row about to be written holds
	 * their basket, not this one's. It cannot be repaired from here -- the cart has
	 * already been filled against the wrong session -- so it is said rather than
	 * fixed.
	 */
	$session_belongs_to = (string) WC()->session->get_customer_id();

	if ( (string) $user_id !== $session_belongs_to && 0 !== strpos( $session_belongs_to, 't_' ) ) {
		fwrite(
			STDERR,
			'The cart being filed under customer ' . $user_id . ' was built for customer '
				. $session_belongs_to . ", so its delivery method is that customer's. Call "
				. 'seed_start_a_cart_for( ' . $user_id . " ) before filling the cart, not after.\n"
		);
	}

	WC()->cart->set_session();
	seed_settle_the_delivery_method();
	WC()->session->save_data();

	$written = $wpdb->replace(
		$wpdb->prefix . 'woocommerce_sessions',
		array(
			'session_key'    => (string) $user_id,
			'session_value'  => maybe_serialize( WC()->session->get_session_data() ),
			'session_expiry' => time() + 2 * DAY_IN_SECONDS,
		)
	);

	if ( false === $written ) {
		fwrite( STDERR, 'Could not write the cart session for user ' . $user_id . "; the storefront will be photographed with whatever WooCommerce chooses.\n" );
	}
}

/**
 * Make the chosen delivery rate survive the customer's first page load, and say
 * which rate the photograph is going to use.
 *
 * Called for you by seed_hand_the_cart_to(). A seed does not need it.
 *
 * Writing `chosen_shipping_methods` is not enough on its own, and this is the one
 * that bites silently, because a session with only that key in it is thrown away
 * before it is ever read. `wc_get_chosen_shipping_method_for_package()` goes back
 * to the default unless all of this holds:
 *
 *     ! $chosen_method || $changed || ! isset( $package['rates'][ $chosen_method ] )
 *         || count( $package['rates'] ) !== $method_count
 *
 * `$changed` comes from `wc_shipping_methods_have_changed()`, which compares the
 * rate ids now on offer against `previous_shipping_methods` in the session, and an
 * absent key reads as `false` -- so every rate list differs from it and every
 * choice is discarded. `$method_count` comes from `shipping_method_counts`, and an
 * absent key reads as `0`, so the count never matches either. Both are needed, and
 * the count is a separate test from the list: writing the list alone still fails.
 *
 * All of which is WooCommerce being careful rather than awkward. Those keys are how
 * it notices that the shop changed underneath a customer who had already chosen,
 * and a seeded session is indistinguishable from exactly that. So the seed has to
 * say what was on offer when the choice was made, and that is bookkeeping no seed
 * should have to know about -- hence here.
 */
function seed_settle_the_delivery_method(): void {
	$packages = WC()->shipping() ? WC()->shipping()->get_packages() : array();

	if ( array() === $packages ) {
		// An empty package list on a cart that needs delivering means the rates
		// were never worked out, so there is nothing to hold and the totals in the
		// picture are wrong too.
		if ( WC()->cart->needs_shipping() ) {
			fwrite( STDERR, "No delivery rates had been worked out for this cart, so the browser will work them out and choose for itself. Call WC()->cart->calculate_totals() before handing the cart over.\n" );
		}

		return;
	}

	$chosen  = (array) WC()->session->get( 'chosen_shipping_methods', array() );
	$offered = array();
	$counted = array();
	$report  = array();

	foreach ( $packages as $index => $package ) {
		$rates = isset( $package['rates'] ) && is_array( $package['rates'] ) ? $package['rates'] : array();

		$offered[ $index ] = array_keys( $rates );
		$counted[ $index ] = count( $rates );

		$stored = isset( $chosen[ $index ] ) ? (string) $chosen[ $index ] : '';

		// What the shop would have settled on with nothing chosen, asked of
		// WooCommerce rather than worked out here: which rates count as collection
		// is its question, and a second opinion on it would drift.
		$default = '';

		if ( array() !== $rates && function_exists( 'wc_get_default_shipping_method_for_package' ) ) {
			$default = (string) wc_get_default_shipping_method_for_package( $index, $package, '' );
		}

		if ( '' !== $stored && ! isset( $rates[ $stored ] ) ) {
			fwrite(
				STDERR,
				$stored . ' is not one of the rates this cart is offered ('
					. ( array() === $rates ? 'none' : implode( ', ', array_keys( $rates ) ) )
					. '), so it will be discarded and '
					. ( '' === $default ? 'WooCommerce will choose' : $default . ' used' )
					. ". A rate id is minted when the method is added to a zone, so check the zones have not been rebuilt or their amounts moved since the choice was made.\n"
			);

			continue;
		}

		if ( '' === $stored ) {
			// Reachable, and the case a seed most needs telling about: a cart can
			// come out of the totals with rates on offer and nothing stored at all,
			// so the browser chooses on its first page load and the seed has no say.
			$report[] = ( '' === $default ? 'nothing stored and nothing to choose' : $default . ', which nothing has stored -- the browser will choose it on the first page load, being the first rate the zone offers' );

			continue;
		}

		/*
		 * Said in terms that are true either way, because the two cases cannot be
		 * told apart from here: a seed that pinned nothing, and a seed whose pin
		 * was replaced during the totals, both leave the default sitting in the
		 * session -- and so does a seed that pinned the default on purpose. What
		 * can be said of all three is that the picture does not depend on the
		 * choice, which is the part worth knowing.
		 */
		$report[] = $stored === $default
			? $stored . '. That is also the rate WooCommerce picks unasked -- the first the zone offers -- so this picture does not depend on any choice being stored, and it moves if the zone is reordered'
			: $stored . ', chosen over WooCommerce\'s own ' . ( '' === $default ? 'default' : $default );
	}

	WC()->session->set( 'previous_shipping_methods', $offered );
	WC()->session->set( 'shipping_method_counts', $counted );

	if ( array() !== $report ) {
		echo 'Delivery method in the photograph: ' . implode( '; ', $report ) . ".\n";
	}
}

/**
 * Remember that the seed made something, so a shot list need not know its id.
 *
 * A shot list carrying `post.php?post=11` is half of one artefact stored in
 * another file: the 11 came out of the seed, and a reseeded shop renumbers it
 * without anything failing. The seed writes down what it made instead, and the
 * shot list says `{{product.the-salt-path-home}}`.
 *
 * The kind is a namespace, so a product and a page that happen to share a slug
 * do not collide, and so the file reads as a list of things rather than a list
 * of numbers.
 *
 * @param string $kind What sort of thing it is: product, order, page, coupon.
 * @param string $key  How a shot list will ask for it, usually its slug.
 * @param int    $id   The id WordPress gave it.
 */
function seed_record_id( string $kind, string $key, int $id ): void {
	$GLOBALS['pc_seed_ids'][ $kind ][ $key ] = $id;
}

/**
 * Close a seed: write the ids down and drop every cache.
 *
 * Called last, after the plugin's own part has run. The cache flush is here
 * rather than in seed_us_shop() because it has to follow the final write, and
 * the ids file is here because until then not everything it names exists.
 */
function seed_finish(): void {
	$ids = $GLOBALS['pc_seed_ids'];
	ksort( $ids );
	foreach ( $ids as &$group ) {
		ksort( $group );
	}
	unset( $group );

	$written = file_put_contents(
		SEED_IDS_FILE,
		wp_json_encode( $ids, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES ) . "\n"
	);

	if ( false === $written ) {
		// Not fatal on its own -- a shot list with no placeholders in it does
		// not need the file -- but silence here becomes a confusing failure in
		// the driver, so say it now while the reason is still to hand.
		fwrite( STDERR, 'Could not write ' . SEED_IDS_FILE . "; shot lists using {{placeholders}} will fail.\n" );
	}

	wp_cache_flush();
	if ( function_exists( 'wc_delete_product_transients' ) ) {
		wc_delete_product_transients();
	}
}
