# Plugin City WordPress / WooCommerce test harness

Disposable WordPress + WooCommerce environment for any Plugin City plugin. Use it locally with Docker, or from any plugin repository as a GitHub Action.

The harness does not contain plugin source. It **mounts** a local plugin directory, installs WordPress and WooCommerce at requested versions, then runs:

1. Generic smoke tests that belong to the harness
2. Plugin-specific tests discovered inside the plugin repository

Use the same harness for `due-date-for-woocommerce`, `order-alert`, `customer-alert`, `stuck-order`, `product-check`, and anything else that follows the same conventions.

## Use as a GitHub Action

Publish this folder as its own GitHub repository. In each plugin repo add `.github/workflows/tests.yml`:

```yaml
name: Tests

on:
  push:
    branches: [main, master]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: OWNER/plugin-city-wp-test-harness@v1
        with:
          plugin-slug: due-date-for-woocommerce
          php-version: "8.3"
          wp-version: latest
          wc-version: latest
          hpos-mode: enabled
          extra-plugin-slug: due-date-for-woocommerce-pro
          extra-plugin-path: due-date-for-woocommerce-pro
```

For Core + Pro, check out both repositories and pass the add-on as `extra-plugin-*`. Activate Core as `plugin-slug` and the add-on as `extra-plugin-slug`.

Replace `OWNER` with the GitHub user or org that owns the harness repo.

Alternatively, call the reusable workflow:

```yaml
jobs:
  test:
    uses: OWNER/plugin-city-wp-test-harness/.github/workflows/reusable-plugin-tests.yml@v1
    with:
      plugin-slug: due-date-for-woocommerce
```

A full copy lives in `examples/plugin-ci.yml`.

## Prerequisites

- Docker Desktop with `docker compose`
- Bash
- PHP CLI (only on the host, used to discover plugin test commands)

The machine that created this harness did not have Docker installed. Install Docker Desktop before starting the environment.

## Directory layout

```
plugin-city-wp-test-harness/
  docker-compose.yml
  docker/php.ini
  config/matrix.tsv
  scripts/
    start.sh
    stop.sh
    reset.sh
    install.sh
    activate-plugin.sh
    deactivate-plugin.sh
    wp.sh
    run-tests.sh
    run-generic-tests.sh
    run-plugin-tests.sh
    run-matrix.sh
    error-log.sh
    screenshot.sh       # photograph the running plugin
    crop-to-frame.py
    contact-sheet.py
  tests/
    generic/          # harness-owned smoke tests
    helpers/          # reusable integration helpers
  .github/workflows/plugin-tests.yml.example
```

Treat this folder as its own repository. Sit it next to plugin folders:

```
plugin-city-wp-test-harness/
due-date-for-woocommerce/
order-alert/
customer-alert/
```

## Point the harness at a plugin

Required inputs:

| Variable | Meaning | Example |
|---|---|---|
| `PLUGIN_PATH` | Absolute or relative path to the plugin directory | `../due-date-for-woocommerce` |
| `PLUGIN_SLUG` | Directory name under `wp-content/plugins` | `due-date-for-woocommerce` |
| `EXTRA_PLUGIN_PATH` | Optional second plugin directory (Pro add-on) | `../due-date-for-woocommerce-pro` |
| `EXTRA_PLUGIN_SLUG` | Directory name for the extra plugin | `due-date-for-woocommerce-pro` |
| `WP_VERSION` | `latest` or a WordPress version tag | `latest` or `6.7` |
| `WC_VERSION` | `latest` or a WooCommerce version | `latest` or `10.0.0` |
| `PHP_VERSION` | `8.1` `8.2` `8.3` `8.4` | `8.3` |
| `HPOS_MODE` | `enabled` or `disabled` | `enabled` |

`PLUGIN_PATH` must be the folder that contains the main plugin file. If `PLUGIN_SLUG` is omitted, the harness uses the directory name.

Mount a Pro add-on beside Core with `EXTRA_PLUGIN_PATH` / `EXTRA_PLUGIN_SLUG`. The harness activates Core first, then the add-on. Leave both unset for a single plugin.

Copy `.env.example` to `.env`, or export the variables in the shell.

## Start, stop, reset

```bash
cd plugin-city-wp-test-harness

PLUGIN_PATH=../due-date-for-woocommerce \
PLUGIN_SLUG=due-date-for-woocommerce \
./scripts/start.sh

./scripts/install.sh
./scripts/stop.sh
./scripts/reset.sh
```

- `start.sh` brings up MariaDB and WordPress and waits until WP-CLI can talk to the site
- `stop.sh` stops containers and **keeps** the database volume
- `reset.sh` removes containers **and** volumes

### Waiting for MariaDB

`start.sh` brings the database up on its own, waits for its health check, and
prints how long it took. A boot that has nothing to compete with takes about
fifteen seconds; the health check allows 180 seconds of grace before a failed
probe counts against it and 60 seconds of counted retries after that, because a
loaded CI runner has hit a 150-second limit and reported a database that was
still starting as permanently broken.

If it never becomes healthy the harness prints the container state, its restart
count, the last five health probes with their output and duration, and the
MariaDB log, rather than leaving Compose's "container is unhealthy" as the whole
story. Restarts above zero mean a crash rather than a slow boot; probes that ran
for the full timeout mean the server was reachable but too busy to answer.

Override the wait with `PC_DB_WAIT_SECONDS`. Keep it in step with
`start_period` plus `retries × interval` in `docker-compose.yml`.

WordPress is published at `http://localhost:8080` (override with `WP_PORT`). Admin user: `admin` / `admin`.

## Change versions

```bash
PLUGIN_PATH=../order-alert \
PLUGIN_SLUG=order-alert \
WP_VERSION=6.7 \
WC_VERSION=10.0.0 \
PHP_VERSION=8.1 \
HPOS_MODE=disabled \
./scripts/reset.sh

PLUGIN_PATH=../order-alert \
PLUGIN_SLUG=order-alert \
WP_VERSION=6.7 \
WC_VERSION=10.0.0 \
PHP_VERSION=8.1 \
HPOS_MODE=disabled \
./scripts/run-tests.sh
```

`WP_VERSION=latest` uses `wordpress:php${PHP_VERSION}-apache`.
A specific version uses `wordpress:${WP_VERSION}-php${PHP_VERSION}-apache`.
Not every WordPress/PHP pair exists as a Docker tag. If Compose cannot pull the image, pick a published combination.

## Run tests

One plugin, current defaults:

```bash
PLUGIN_PATH=../due-date-for-woocommerce \
PLUGIN_SLUG=due-date-for-woocommerce \
WP_VERSION=latest \
WC_VERSION=latest \
PHP_VERSION=8.3 \
HPOS_MODE=enabled \
./scripts/run-tests.sh
```

That command starts the environment, installs WordPress and WooCommerce, applies HPOS, activates the plugin, runs generic tests, then discovers and runs plugin tests.

Individual commands:

```bash
./scripts/run-generic-tests.sh
./scripts/run-plugin-tests.sh
./scripts/activate-plugin.sh
./scripts/deactivate-plugin.sh
./scripts/wp.sh plugin list
./scripts/error-log.sh
```

## Generic tests

Owned by the harness. They do not mention Due Date or any other product:

- WordPress boots
- WooCommerce is active
- the mounted plugin is active
- an extra mounted plugin is active when `EXTRA_PLUGIN_SLUG` is set
- the plugin deactivates and WordPress still boots
- no PHP fatal on bootstrap / storefront
- WooCommerce inactive: storefront and wp-admin must not fatal, and the plugin stays active
- HPOS matches `HPOS_MODE`
- `wp-login.php` and `wp-admin` respond
- real admin screens render for a signed-in administrator, with and without WooCommerce
- a customer, simple product, variable product, shipping zone, and order can be created

Admin screens are requested as a signed-in administrator on purpose. An
anonymous `/wp-admin/` request only returns the login redirect, so no admin
screen is built and `admin_notices`, `admin_init` and `admin_post_*` never run.
A plugin that reaches for a WooCommerce-only class on one of those hooks looks
perfectly healthy until someone actually loads a page, which is the gap these
checks close.

Skip groups with `PC_SKIP_GENERIC_TESTS=1` or `GENERIC_TEST_WC_INACTIVE=0`.

## Plugin-specific tests

Plugin-specific tests stay in the plugin repository. The harness never hardcodes them.

Discovery order:

1. `PLUGIN_TEST_COMMAND` if set
2. executable `tests/run-harness.sh` (plugin takes full control)
3. first matching `composer.json` script that looks like a shell command:
   `plugin-city-tests`, `test:wp`, `test:integration`, `test`
4. `php tests/run-tests.php` if that file exists
5. `wp eval-file tests/wp-integration.php` if that file exists
6. executable `bin/plugin-city-tests.sh`

If nothing is found, plugin tests are skipped and the harness still reports generic results.

Commands run inside the WP-CLI container with the working directory set to the mounted plugin. Helpers are available at `/opt/pc-harness/tests/helpers`.

Example plugin integration test:

```php
<?php
require_once getenv('PC_HARNESS_ROOT') . '/tests/helpers/load.php';

$product = PluginCity\Harness\create_simple_product();
$order   = PluginCity\Harness\create_order(array('product' => $product));
```

`PC_HARNESS_ROOT` is `/opt/pc-harness` inside the environment.

### Asking whether an asset arrived, when the handle is somebody else's

A test that asks `wp_style_is()` or `wp_script_is()` about a handle **another
plugin registers** will answer no here even when the plugin under test is doing
everything right. Register the handle yourself first:

```php
wp_register_style( 'woocommerce_admin_styles', WC()->plugin_url() . '/assets/css/admin.css', array(), WC_VERSION );

Plugin::instance()->enqueue_admin_assets( 'woocommerce_page_my-settings' );

PluginCity\Harness\assert_true( wp_style_is( 'woocommerce_admin_styles', 'enqueued' ), 'The picker is given its stylesheet' );
```

Two things combine to produce that false negative, and neither shows up in a
browser:

- Plugin tests run under `wp eval-file`, and WP-CLI fires neither `admin_init`
  nor `admin_enqueue_scripts`. WooCommerce registers its admin script and
  stylesheet on the first of those, so in here nothing has registered them.
- `wp_enqueue_style()` of a handle nothing has registered is parked in
  `WP_Dependencies::$queued_before_register`, which is private, rather than
  going on the queue. `wp_style_is( …, 'enqueued' )` reads the queue, so it
  answers no.

On a real admin request the order is harmless: `WP_Dependencies::add()` empties
that parked list as soon as the handle turns up, so the enqueue lands. Only a
request where the handle never gets registered at all can see it, which is why
this is a `wp eval-file` problem specifically.

Worth spending the paragraph on because the failure points the wrong way. The
test reads as "the plugin did not ask for the stylesheet", which is a real fault
worth writing a test for — a borrowed picker given its script and not its
stylesheet draws itself unstyled on top of the plain control it was meant to
replace — so the obvious next move is to go looking in the plugin for a bug that
is not there.

## Add another Plugin City plugin

1. Keep the plugin in its own folder with its own tests
2. Point the harness at it — do not change harness code

```bash
PLUGIN_PATH=../stuck-order \
PLUGIN_SLUG=stuck-order \
./scripts/run-tests.sh
```

Each plugin should expose at least one of the discovery files above. That is the only contract.

## Version matrix

`config/matrix.tsv` is a **small default matrix**, not every Cartesian combination:

| PHP | WordPress | WooCommerce | HPOS |
|---|---|---|---|
| 8.3 | latest | latest | enabled |
| 8.3 | latest | latest | disabled |
| 8.1 | latest | latest | enabled |
| 8.4 | latest | latest | enabled |
| 8.3 | 6.7 | latest | enabled |
| 8.3 | latest | 10.0.0 | enabled |

```bash
PLUGIN_PATH=../due-date-for-woocommerce \
PLUGIN_SLUG=due-date-for-woocommerce \
./scripts/run-matrix.sh
```

Each row resets volumes so image and database state do not leak. Edit the TSV to add or remove rows.

## Shared helpers

| Helper | Use |
|---|---|
| `create_customer()` | Test customer user |
| `create_simple_product()` | Published simple product |
| `create_variable_product()` | Variable product with two variations |
| `create_order()` | Order with a line item |
| `ensure_basic_shipping()` | Zone with flat rate and local pickup |
| `add_order_shipping()` | Shipping line on an order |
| `enable_hpos()` / `disable_hpos()` | Toggle HPOS |
| `error_log_contents()` / `clear_error_logs()` | Inspect PHP / WP debug logs |
| `assert_true()` / `assert_same()` | Tiny assertions |
| `seed_us_shop()` | A US shop in dollars, for screenshots — see below |
| `seed_record_id()` / `seed_finish()` | Record what a seed made, so a shot list need not know ids |

Load them with:

```php
require_once getenv('PC_HARNESS_ROOT') . '/tests/helpers/load.php';
```

WP-CLI passthrough:

```bash
./scripts/wp.sh wc --version
./scripts/wp.sh eval 'echo wp_timezone()->getName();'
```

## Screenshots

The harness can photograph the plugin it is running. `scripts/screenshot.sh`
walks a list of shots, renders each one in headless Chrome against the live site,
and crops every picture to the subject the page marked for itself. Four shots
take about twenty seconds, and the same shot list against the same seeded shop
comes back byte for byte the same, so a restyled settings screen or a renamed
field means re-running one command rather than spending an afternoon with a
screenshot tool.

```bash
PLUGIN_PATH=../my-plugin PLUGIN_SLUG=my-plugin ./scripts/install.sh

# Build the shop. The seed belongs to the plugin; see below.
./scripts/wp.sh eval-file \
  /var/www/html/wp-content/plugins/my-plugin/.screenshots/seed.php

./scripts/screenshot.sh ../my-plugin/.screenshots/shots.tsv dist/screenshots
python3 scripts/contact-sheet.py ../my-plugin/.screenshots/shots.tsv dist/screenshots
```

Two of those files belong to the plugin and not to the harness, because both are
editorial rather than mechanical: the **seed** that builds a believable shop, and
the **shot list** that says which screens sell the plugin. Everything that would
otherwise have to be worked out once per product lives here.
`examples/screenshots.tsv` is a worked shot list, kept as the format's
documentation.

### The shot list

One line per shot, tab separated. Blank lines and `#` comments are ignored.

| Column | Meaning |
|---|---|
| `name` | Output file stem, so `screenshot-1` writes `screenshot-1.png` |
| `path` | Site-relative, e.g. `/product/a-book/` or `/wp-admin/admin.php?page=my-settings`. May carry `{{kind.key}}` placeholders |
| `frame` | CSS selector list. The **union** of every match is what gets cropped to |
| `click` | Selector clicked before the frame is measured, or `-` |
| `pad` | Page pixels kept around the subject |
| `margin` | Flat pixels of page colour added after cropping |
| `width` `height` | Viewport in CSS pixels. The height only has to be enough to hold the subject, since the crop decides the result |
| `caption` | Optional. The readme caption this shot answers. The capture ignores it; `contact-sheet.py` reads it |

The frame is the union of every match rather than the first because wp-admin lays
its columns out with floats: the wrapper that looks like the subject measures a
few pixels high, and a frame drawn round it photographs a strip of nothing.

Everything is rendered at device scale 2 and halved, because Chrome's 2x text
downsampled is visibly cleaner than its 1x, and the published sets in this range
are 1x. Deleting the `.resize()` in `scripts/crop-to-frame.py` doubles every
dimension from the same raw renders, with no recapture.

A selector that matches nothing fails the run. Nothing warns you that a frame has
quietly got *bigger*, which is the maintenance surface to watch: compare a new
capture against the committed one before believing it.

### What reseeding costs you

Capture is reproducible; a shop is not. Re-run the driver against a shop already
built and every file comes back identical. Rebuild the shop first and any screen
printing a value the database chose will differ, because two of those values are
not the seed's to choose:

- **An id from a sequence.** WordPress hands out post ids in order and, with HPOS
  on, orders draw from the same pool as posts, so each reseed lands the order a
  few numbers further on. `#31` is not a number a seed can ask for.
- **A wall clock.** WooCommerce stamps order notes with the time they are written,
  and `maybe_set_date_paid()` stamps a paid order with `time()` rather than with
  the date the order was created. A shot of an order therefore carries this
  afternoon in it.

The second one a seed can fix, and a seed photographing an order should:
`$order->set_date_paid( $order->get_date_created() )` after the status is set puts
the payment on the day the order says it was placed, which is what the picture
ought to show anyway. The first one it cannot, so treat a difference confined to
an id or a timestamp as the shop having been rebuilt, and compare the rest of the
frame before going looking for a bug.

### The seed, and the part of it that is shared

`tests/helpers/seed-common.php` holds the part of a seed that is the same
whatever the plugin is. Two calls, one at each end:

```php
require_once getenv( 'PC_HARNESS_ROOT' ) . '/tests/helpers/seed-common.php';

PluginCity\Harness\seed_us_shop( array(
    'name'     => 'Thornbury Books',
    'address'  => '1408 NE Alberta St',
    'city'     => 'Portland',
    'postcode' => '97211',
) );

// ... the plugin's own catalogue, its own settings, and whatever state its
// captions need. This part is irreducible and nobody can share it.

PluginCity\Harness\seed_record_id( 'product', 'the-salt-path-home', $id );
PluginCity\Harness\seed_finish();
```

`seed_us_shop()` puts the shop in the United States, in dollars, with US date
order, and takes the two WooCommerce switches described below out of the way.
Overrides are one array of named keys so a seed states only its differences — a
bookshop and a hardware shop are not in the same town. `seed_finish()` drops the
caches and writes the ids down, and both of those have to happen after the last
write rather than after the shared ones, which is why the pair is a bookend.

`WP_TIMEZONE` sets the timezone `install.sh` applies, for the sake of a suite that
wants a fixed one. A seed sets its own anyway: the shop in the picture is in a
town, and the seed is what knows which.

### Ids stay out of the shot list

A path that says `post.php?post=11` is half of one artefact filed in another
place. The 11 came out of the seed, and reseeding the shop renumbers it without
anything failing — the run photographs whatever is at that id now, so the set
comes back wrong rather than missing, which is the expensive way round.

So the seed records what it made and the shot list asks for it by name:

```
screenshot-2	/wp-admin/post.php?post={{product.the-salt-path-home}}&action=edit	…
```

`seed_record_id( 'product', 'the-salt-path-home', $id )` writes that into
`pc-seed-ids.json` inside the disposable WordPress volume, and the driver fills
it in before rendering. A placeholder nothing recorded **stops the run**, names
itself, and lists what the seed did record under that kind. Leftover braces stop
it too, so a mistyped placeholder cannot slip through as literal text and answer
404 at a URL that then photographs perfectly well.

### What the machine needs

- **Headless Chrome on `PATH`**, as `google-chrome` or `chromium`.
- **Python 3 with Pillow**, for `crop-to-frame.py` and `contact-sheet.py`.
- **Fonts, if you generate any imagery of your own.** A box missing the face a
  set was drawn with substitutes another one silently, and the letterforms change
  with nothing to say so.

### The shim mints a login cookie, and must stay in the container

`scripts/screenshot.sh` writes a must-use plugin into the WordPress volume with a
token generated for that run, and on a request carrying that token it **generates
a valid authentication cookie** for the admin user. That is the only way to photograph
wp-admin without driving a login form, and it is indefensible anywhere a real
site could reach it.

It is therefore installed into the disposable volume, deleted when the driver
exits, and goes with the volume in any case. Do not copy
`tests/helpers/screenshot-mode.php` into a plugin, and do not adapt it into
anything that ships. The harness is the right home for it precisely because the
harness is thrown away.

### Two traps that look like broken code

Both of these cost real time, neither logs anything, and both look like a fault
in the plugin or a broken install.

**A new store sits behind WooCommerce 11's Coming soon page.** Every storefront
URL answers **HTTP 200** with a `wp-block-woocommerce-coming-soon` holding page.
No error is raised and nothing is logged, so a capture succeeds, writes a file of
the expected size, and the file is a picture of a holding page. `seed_us_shop()`
clears it, and a seed that does not use the helper needs both options:

```php
update_option( 'woocommerce_coming_soon', 'no' );
update_option( 'woocommerce_store_pages_only', 'no' );
```

Both, not one. With `woocommerce_store_pages_only` left at `yes` the shop and
product pages stay behind the page while the rest of the site comes out, which
reads as the first option not having worked.

**Drive `docker compose` through this repo's scripts, never directly.**
`scripts/lib.sh` sets `COMPOSE_PROJECT_NAME`, and it also decides which Compose
files are in play. A bare `docker compose` in this directory therefore addresses
a *different* project: `docker compose up` starts a second stack that fights the
first for port 8080, and `docker compose logs` shows an empty one while the real
containers carry on somewhere you are not looking. The result reads exactly like
a broken install.

Use `./scripts/start.sh`, `./scripts/stop.sh`, `./scripts/reset.sh` and
`./scripts/wp.sh`. If you need Compose itself, source the library first so the
project name matches:

```bash
source scripts/lib.sh && pc_load_env && pc_compose logs wordpress
```

## GitHub Actions

GitHub-hosted runners already have Docker, so plugin CI does not need Docker Desktop.

**Action inputs**

| Input | Default | Meaning |
|---|---|---|
| `plugin-slug` | required | Folder name under `wp-content/plugins` |
| `plugin-path` | `.` | Plugin directory in the caller repo |
| `php-version` | `8.3` | `8.1` `8.2` `8.3` `8.4` |
| `wp-version` | `latest` | WordPress version or `latest` |
| `wc-version` | `latest` | WooCommerce version or `latest` |
| `hpos-mode` | `enabled` | `enabled` or `disabled` |
| `plugin-test-command` | empty | Override discovered plugin tests |

The harness repository also runs `harness-self-test.yml` against `fixtures/sample-plugin` so the Action is verified independently of any real plugin.

## Limitations

- Docker is required. There is no native WP-CLI fallback in this harness
- Official `wordpress:VERSION-phpX.Y-apache` tags do not exist for every pair
- `wordpress:cli-phpX.Y` must exist for the chosen PHP version
- Generic tests talk to the WordPress container as `http://wordpress` (Compose network name). The host browser uses `http://localhost:8080`
- HPOS is toggled with WooCommerce options. Very old WooCommerce versions may ignore those options
- Plugin tests that need Composer packages must vendor them in the plugin; the WP-CLI image does not install plugin `vendor/` for you
