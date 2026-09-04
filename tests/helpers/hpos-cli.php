<?php
/**
 * Apply HPOS_MODE during install. Loaded with: wp eval-file
 *
 * @package PluginCity\Harness
 */

require_once __DIR__ . '/load.php';

if ( ! class_exists( 'WooCommerce' ) ) {
	fwrite( STDERR, "WooCommerce is not active; cannot apply HPOS mode.\n" );
	return;
}

PluginCity\Harness\apply_hpos_mode();
echo 'HPOS ' . ( PluginCity\Harness\hpos_is_enabled() ? 'enabled' : 'disabled' ) . PHP_EOL;
