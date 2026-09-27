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
 * @var array<string,array<string,int>>
 */
$GLOBALS['pc_seed_ids'] = array();

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
