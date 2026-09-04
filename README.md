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
```

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
| `WP_VERSION` | `latest` or a WordPress version tag | `latest` or `6.7` |
| `WC_VERSION` | `latest` or a WooCommerce version | `latest` or `10.0.0` |
| `PHP_VERSION` | `8.1` `8.2` `8.3` `8.4` | `8.3` |
| `HPOS_MODE` | `enabled` or `disabled` | `enabled` |

`PLUGIN_PATH` must be the folder that contains the main plugin file. If `PLUGIN_SLUG` is omitted, the harness uses the directory name.

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
- the plugin deactivates and WordPress still boots
- no PHP fatal on bootstrap / storefront
- WooCommerce inactive request (plugin must not fatal)
- HPOS matches `HPOS_MODE`
- `wp-login.php` and `wp-admin` respond
- a customer, simple product, variable product, shipping zone, and order can be created

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

Load them with:

```php
require_once getenv('PC_HARNESS_ROOT') . '/tests/helpers/load.php';
```

WP-CLI passthrough:

```bash
./scripts/wp.sh wc --version
./scripts/wp.sh eval 'echo wp_timezone()->getName();'
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
