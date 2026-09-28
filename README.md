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
    host/             # checks on the harness scripts themselves, run outside the containers
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

### Fetching the images

`start.sh` fetches whichever of the three images this machine has not got before
it starts anything, and gives each one three attempts, ten and twenty seconds
apart. `PC_PULL_ATTEMPTS` and `PC_PULL_RETRY_SECONDS` change that budget, and
`PC_PULL_ATTEMPTS=1` turns the retry off.

Compose would fetch them anyway as part of `up`. Doing it first is what makes a
retry possible at all: left where it was, the fetch is half of the command that
starts the database, so a dropped connection kills the whole `up` before the
harness has reached the database wait and said anything. A job that failed that
way reads as one line about a manifest, with nothing to say that no code had run.

Only a missing image is fetched, which is what `up` did. A moving tag such as
`mariadb:11` or `wordpress:php8.3-apache` is not refreshed by either, so a
machine that already holds the three images still starts with no registry
reachable at all.

**What is retried, and what deliberately is not.**

- **A registry that cannot be reached, or that drops the connection.** This is
  the one worth covering: it fails in seconds, it usually succeeds on the next
  attempt, and it has already failed a real job 3.5 seconds in, before a line of
  anybody's code had run.
- **A registry that answers and refuses is tried once.** A tag or a repository
  that does not exist, or one that needs credentials this machine has not got, is
  the same answer every time, so three of them only print it later. Not every
  WordPress and PHP pair is a published tag, and that is the usual way to meet
  this one; the failure says so and points at `WP_VERSION` and `PHP_VERSION`.
- **A database that comes up and fails its health check is not retried**, and the
  retry is around the fetch alone for that reason. It is a real failure, and it
  takes the whole health budget below to produce, so a second and third go turn a
  red job into a slow red job.
- **Nothing after the containers start is retried.** The WordPress install, the
  WooCommerce download, and every test fail once, on purpose.

A fetch that uses up its attempts says so, in those words and with the number,
because a job that failed three times should not read like a job that failed once
and get re-run on a guess:

```
=== Could not pull wordpress:php8.3-apache after 3 attempts ===
Every attempt failed to reach or finish with the registry, and what
it said last is above. Nothing in the plugin and nothing in this
harness has run yet, so this is not a test result.

3 failures in a row is more than a dropped connection, so
re-running the job is a guess rather than a fix. Check that the
registry is reachable from this machine first.
```

`tests/host/pull-retry.sh` proves all three behaviours against a throwaway
Compose file — a host that does not resolve is tried three times, a tag Docker
Hub refuses is tried once, and an image already on the machine is not fetched at
all. It starts no containers, so it is safe to run beside a stack that is up.

A registry failure that this does not cover can still arrive wearing something
else's clothes. That is under
[Two failures that are the harness and not the plugin](#two-failures-that-are-the-harness-and-not-the-plugin).

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
| `seed_start_a_cart_for()` | Begin a basket as the customer the shots are taken as |
| `seed_hand_the_cart_to()` | Give that basket, and its chosen delivery method, to them |
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
  /var/www/html/wp-content/plugins/my-plugin/tests/screenshots/seed.php

./scripts/screenshot.sh ../my-plugin/tests/screenshots/shots.tsv dist/screenshots
python3 scripts/contact-sheet.py ../my-plugin/tests/screenshots/shots.tsv dist/screenshots
```

The paths in that block are not all on the same side of the mount, and the two
middle lines are where it shows. `scripts/wp.sh` is WP-CLI **inside** the
container, so the seed is named at its path in there; `scripts/screenshot.sh`
reads the shot list **here on the host** and writes the pictures beside you, so
it is named at its path in the plugin's repository. Copying a kit in with
`docker cp` and then reaching for the container's path for both is the mistake
this is worth spelling out for — the script says so if you do.

Two of those files belong to the plugin and not to the harness, because both are
editorial rather than mechanical: the **seed** that builds a believable shop, and
the **shot list** that says which screens sell the plugin. Everything that would
otherwise have to be worked out once per product lives here.
`examples/screenshots.tsv` is a worked shot list, kept as the format's
documentation.

Where in the plugin's repository they live is the plugin's decision.
`tests/screenshots/` is what the plugins written against this harness use, so it
is worth copying for the ordinary reason that a reader of a second plugin then
already knows where to look. It is a convention and not a requirement — every
path is passed in, so nothing here assumes one.

The example above puts it inside the plugin folder, which is the arrangement
`eval-file` can reach through the mount. Three things to weigh before copying
that part:

- **Whether the folder ships is decided by the plugin's build, and only the
  built archive can tell you.** An exclusion list catches the directory names
  somebody thought of and nothing else; a build that refuses hidden paths
  outright turns a dot-directory into a failed build rather than a leak. So the
  name the folder is given, and whether it begins with a dot, decide nothing on
  their own. Read the release instead: `unzip -l` the archive and look for the
  seed.
- **A kit that drives more than one edition belongs to the repository rather
  than to a plugin folder.** Once it resets the database, builds the archives
  and photographs whichever edition it is told to, putting it inside one plugin
  folder makes that plugin the owner of the tooling that publishes the other.
  The repository root is the honest home for it, and the folder is then outside
  every build by construction rather than by exclusion.
- **A set photographed from a built archive is not in the mount at all**, which is
  the arrangement to prefer: the pictures are then of the plugin a shop installs
  rather than of a working tree with test files in it. Mount the extracted build
  as `PLUGIN_PATH` and `docker cp` the seed into the container before running it.
  A kit at the repository root has to do this anyway, since nothing outside the
  plugin folder is mounted.

### The shot list

One line per shot, tab separated. Blank lines and `#` comments are ignored.

| Column | Meaning |
|---|---|
| `name` | Output file stem, so `screenshot-1` writes `screenshot-1.png` |
| `path` | Site-relative, e.g. `/product/a-book/` or `/wp-admin/admin.php?page=my-settings`. May carry `{{kind.key}}` placeholders, and may be prefixed with who is looking |
| `frame` | CSS selector list. The **union** of every match is what gets cropped to, and every selector in it has to match something |
| `click` | What to do before the frame is measured, or `-`. One step, or several separated by `\|`. A step is a selector to click; a step written `selector ::= value` types the value into that field instead |
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

**Every selector in the list has to match something with a size**, and one that
does not refuses the shot and names itself:

```
part of the frame is not on this page, so the crop would be narrower than the
shot asked for: ".mypl-settings__heder" matches nothing on this page
```

The strict rule is worth the inconvenience because the alternative is silent: a
frame of two selectors where one is a typo would draw itself from the other and
save a picture simply narrower than the one asked for, which is the worst shape a
fault can take here. An element that is present but measures a pixel or less
counts as absent too, since it contributes nothing to the box either way.

Where a frame genuinely means "whichever of these the page has", say so in the
selector — `:is(.new-card, .old-card)` is one selector, still has to match, and
reads as a decision rather than as a list somebody got wrong.

What none of this catches is a frame that has quietly got *bigger*, so that is
the maintenance surface left: compare a new capture against the committed one
before believing it.

With `pad` at `0` the crop is flush to the subject less the two pixels the rule
itself occupies, so a subject whose own border is part of the picture wants
`pad 2` or more. It is worth setting anyway: a screen photographed hard against
its outermost element reads as a cut-out rather than as a screen.

### Who a shot is taken as

A bare path is photographed as the administrator, which is right for wp-admin and
wrong for everything else. A storefront shot is a *shopper's* screen, and a shopper
is usually not an administrator: photograph the cart as one and the picture
carries an administrator's view of the shop into a page meant to show a
customer's. WooCommerce's Coming soon page is the sharp end of that — an
administrator is let through it and a shopper is not, so a set taken entirely as
the administrator can photograph a shop no customer can reach, at the expected
size, with nothing logged.

So a path may say who is looking, before the slash:

```
screenshot-3	visitor:/cart/	.wp-block-woocommerce-cart	…
screenshot-4	jo:/my-account/orders/	.woocommerce-MyAccount-content	…
```

`visitor` is the reserved word for nobody: the page is rendered with no session
at all. Anything else is a WordPress login, and a login the site has never heard
of **stops the run** rather than being quietly photographed signed out — which
otherwise looks like a shop with an empty basket.

A path always begins with a slash, so a prefix can never be mistaken for part of
a URL.

Each shot gets a fresh browser profile, so a signed-out shot stays signed out
however many signed-in shots came before it. A shot taken as somebody other than
the administrator is rendered twice in the warm-up pass described below, once as
the administrator so that the site has finished writing whatever a first
privileged view writes, and once as the person who will be photographed.

### Screens that have to be asked before they have anything on them

Some screens cannot be reached by asking for a URL. A panel that answers a form
has nothing on it until the form has been filled in and submitted, and a picture
of the empty one is a picture of a feature not working. So the `click` column
takes a sequence:

```
name	/wp-admin/admin.php?page=my-settings	#answer	[data-section="try-it"]|#subtotal ::= 78.50|#items ::= 6|.card button[type="submit"]	…
```

Steps are separated by `|` and taken in order: click the nav entry, fill three
fields, press the button. `::=` splits a step into a selector and the value to
type; everything after the first `::=` is the value, so a value may contain the
token. A field is filled the way a person fills it — the value is set and then
`input` and `change` are dispatched — because a screen that redraws itself when a
field changes has to be given the chance to.

Both tokens came from the first shot list that needed a sequence, and they were
kept for opposite reasons. `::=` cannot be mistaken for CSS: a selector may
contain colons, but nothing in the language puts an equals sign after a
pseudo-element. `|` can be mistaken for CSS, in `[lang|="en"]`, and a value a
shop types could contain one too. There is no separator that could not, in a
column that carries arbitrary strings inside a file whose columns are already
separated by tabs — so the collision is made loud rather than legislated away. A
selector cut in half either stops being a selector the browser will parse or
stops matching anything, and both refuse the shot and name the step.

**A step that did not happen refuses the shot.** Not a warning, and not carrying
on to the next one: a form filled in with two of its three fields photographs
exactly as well as one filled in with three, and so does a panel that was never
asked anything. So the run stops, and says which step and why:

```
step 5 of 8 did not happen: "#tester-class" would not take "no-such-class" and reads ""
step 3 of 8 did not happen: the browser does not understand "#tester-weight[" as a selector
step 4 of 8 did not happen: nothing on this page matches "#tester-nothing"
```

The last of those three is the one worth knowing about. A menu quietly refuses a
value it has no entry for and reads back empty, so a shot list naming a shipping
class the shop has not got would otherwise photograph a form with one field
blank — which is a wrong picture of a working feature.

A sequence that ends by submitting a form is the case all of this was built for,
and there are two things to get right in a shot list that does it.

- **The form has to post to the URL it was drawn from.** Everything the shim
  needs is on the query string, so a form whose `action` is empty — which is what
  WordPress and WooCommerce write — comes back with the shot still in progress. A
  form posting somewhere else arrives as a page the shim was never asked to mark,
  so nothing draws a rule at all and the run stops for want of one.
- **The frame should name something that only exists once the screen has
  answered.** Every selector in a frame has to match, so a frame that includes
  the answer is a check on the answer having arrived: an unanswered screen has
  nothing for that selector to find and the shot is refused. It may sit beside a
  wrapper selector — both have to match — so the frame can be the shape of the
  picture and the proof at the same time.

Only the last step may submit, and the sequence has to be the whole of what the
shot does. Following a plain link is refused rather than supported — put its
destination in `path` instead.

### Nothing is saved unless the page says it drew itself

A screen that loads its own content — over admin-ajax, the REST API, WooCommerce's
Store API — is the one that photographs wrongly without looking wrong. It has two
faces and only one of them is obvious. A panel whose request is refused renders as
an empty gap, which anybody would notice. A basket whose request is refused draws
an error banner *after* the frame has been measured, so the rule stays where it was
put, the subject slides down behind it, and the crop comes out the banner's height
too high — at a plausible size, in the right place, looking exactly like a
screenshot.

There is one render and no channel back out of it, so the page's verdict on itself
travels as the **colour of the rule** it drew. `crop-to-frame.py` holds the same
table and is the only thing that reads it:

| Rule | Meaning |
|---|---|
| magenta | The page finished drawing itself. Crop it |
| green | Something the page needed did not arrive, or a warning would have been left out of the picture |
| cyan | A request had not answered when the picture was taken |
| yellow | The subject was still moving when the picture was taken |
| red | The shot list names something this page has not got: an `allow` line for a request it never makes, or a frame selector that matches nothing |
| blue | A step in the `click` column did not happen, or the form it submitted was turned away |

Five of the six **stop the run**, name the reason, and save nothing. The render
that was refused is kept beside the set as `<name>.rejected.png`, at twice final
size, with the reason written across the top of it — and last run's picture is
deleted before this run's is attempted, because a refusal that left the old file in
place would leave a set looking complete and current when one of its screens had
not been photographed at all.

What the page asserts is deliberately positive. Not "no error text on the screen",
which only ever catches the failures somebody had already thought of, but: every
same-origin request this page made in order to draw itself finished and answered,
and the subject measures the same twice running. Requests to other origins are
left out, because a page reaching a third party is not the page drawing itself,
and in a container with no route to one every such request fails whether or not
anything is wrong. The cropper adds the one assertion the page cannot make about
itself — that the rule closes on all four sides, so the subject was not bigger
than the viewport it was rendered in.

An `<img>` is counted too, and it has to be counted separately, because an image
is neither of the two things a page fetches through script. Nothing wraps it: the
browser goes and gets it, and a failure arrives as an `error` event on the element
rather than as a rejected promise or a status code anything can read. So a shot
whose subject *is* a photograph could fail with nothing to show for it, and one
did — a product tile with a broken image and a cart badge that never drew, at
exactly the right size, on one run in three. Two things answer for it now. Any
same-origin element that fails to load is heard on a capturing `error` listener,
which is the only way to hear one, since a resource error does not bubble; and an
image that has simply not finished counts towards the same "not answered yet" as
an outstanding request, so the picture waits for it rather than being taken past
it. The first covers a stylesheet and a script as well, which is why the sentence
the refusal prints names the URL rather than the kind of thing it was.

The driver adds the half of that a browser cannot do. The warm-up pass fetches
each page with `curl`, which is the one moment in a capture when something can
read a response header, and the shim says in a header who it signed in and which
cookie carries the session. A run stops there if the site signed in somebody else,
signed in nobody, or signed its own render in without sending the browser a
cookie — the last being the fault this whole section was built around, since a page
authenticated for itself and anonymous for everything it loads is exactly how the
empty gap and the too-tall crop were produced.

A request that never answers at all is not a verdict, because Chrome's virtual
clock stops while a fetch is outstanding: the render waits for it. Wait long enough
and the driver kills the browser with no file written, and the run says `FAILED to
render` and stops. So a slow screen is photographed correctly and a hung one is
refused; the cyan verdict is the backstop for the day Chrome's clock behaves
differently.

Submitting a form is the one thing the count cannot see, and it is worth being
exact about why. What is counted is what a page fetches *for itself*; a submission
is a navigation, so the POST is not a request that document ever makes — it is the
reason the next document exists. Two things answer for it instead. The steps are
remembered in `sessionStorage`, which is what survives a navigation in the same
tab, so the page that comes back can tell that a sequence ran, that it ran to the
end, and that it arrived as the answer to a POST rather than as an ordinary page
load. And a nonce that a POST had turned away is a refusal in its own right,
because a screen whose nonce was refused draws exactly as it draws when nothing
has been asked: right size, no error, nothing in any log. That is not a
hypothetical — it is how a picture of an unanswered panel came to be published
once, and the cause was a session token that changed between the page being drawn
and the form being posted.

One consequence to know about, since it is a refusal you cannot argue with: a
screen that checks two nonces in turn and accepts the second is refused, because
the first was turned away. Nothing in this range does it on a form a capture
submits, and the message names the action so at least the cause is not a mystery.

#### Excusing one request, on one shot

A screen may ask for something that is never going to arrive and draw itself
perfectly anyway. WooCommerce 11.1 does it on the cart: a block theme's header
carries a Mini Cart, that block is deliberately not rendered on the cart page, and
the script module it registers is loaded regardless — so the module asks for a REST
route it was never told the address of, gets a 404, and retries for as long as the
page is open. Nothing on the screen depends on it.

A shot list can say so, in a line of its own:

```
allow	cart	undefinedwc/store/v1/cart	The Mini Cart is not rendered on the cart page, so the script module it registers never learns where the REST API is. Nothing on the page depends on the answer.
```

Four fields, all required: the word `allow`, the name of **one** shot, a piece of
the URL, and why it does not matter. The reason is required because the next person
to read the file is the one who has to decide whether it is still true.

This is the only way past the check and it is meant to be awkward. It names one
request on one screen rather than a kind of error anywhere, and it has to keep
being needed: a fragment nothing on that page asks for any more turns the rule red
and refuses the shot, because an exception that has stopped applying is a hole in
the check that nobody knows is open. An `allow` line naming a shot that is not in
the list stops the run before anything is rendered.

### Photographing two editions in one container

A plugin sold as a free build and a paid one needs both photographed, and the paid
build is usually the free build with a directory added to it. So the cheap way is
one container: mount a stable directory, put the free build's contents in it,
capture, then replace the contents with the paid build's and capture again. That
works, and both of the things that go wrong the first time go wrong quietly enough
to be worth writing down.

**Swap the contents, not the directory.** A bind mount resolves to an inode, so
deleting the mounted directory and putting a new one in its place leaves the
container looking at something that no longer has a name. Empty the directory and
copy into it.

**Then make the container read the new files.** PHP keeps compiled scripts, and the
file a swap most needs re-read is the plugin's main file — which in this
arrangement is the one that differs, because the line loading the paid directory is
in it and in nothing else. Leave the process as it is and the paid classes are
absent from every web request while `wp` sees all of them, because the CLI is a
separate process with a cache of its own. What that looks like from here is a paid
feature that reports itself switched on from the command line and is simply not on
the page, which reads as a bug in the plugin. Restart the web container after the
swap and wait for the site to answer before going on.

**And check what an edition's own licensing wants done before its settings are
written.** This is not the harness's business, but it is the harness that finds
out: a paid build with no licence key typically grants itself a grace period from
the moment it records having been installed, and a build asked to decide whether a
missing record means "never run here" or "record deleted to ask for a second
grace" will go by whether its own options are already in the database. Seed the
paid settings first and the grace is spent before it starts. Every paid feature
then denies, and the first thing to say so is a frame selector matching nothing.
Whatever writes that record — activating the plugin with the paid directory in
place, or a first admin request — belongs before the seed rather than after it.

### What makes a capture reproducible

Three things the driver does that only make sense once you have seen a set fail to
reproduce, because none of them announces itself and none of them fails:

- **Every path is rendered once before any of it is photographed.** A first
  signed-in view of a site is not like the views after it. WordPress writes a
  navigation menu out of the theme's fallback the first time somebody who may edit
  one looks at a page, and WooCommerce hooks its header icons in around it, so a
  storefront shot taken on a site nobody had visited had a header fourteen pixels
  shorter than the same shot on the next run.
- **The crop rule waits for the page to go quiet**, not for a fixed delay. A
  variable product's form runs on jQuery and can empty the image column after the
  load event.
- **Images are eager and decode synchronously, and transitions are off.** Chrome
  will paint before an asynchronous decode finishes, and a gallery that fades on a
  CSS transition is not touching the document while it fades, so no amount of
  waiting for quiet catches it.
- **An animation that never ends is stopped before the picture is taken.** A
  progress bar with barber-pole stripes is somewhere different in its cycle every
  render, so two runs of one shot list came back as the same set except for a
  single band of a single picture. Nothing failed and both pictures looked right.
  Only the endless ones are stopped, and not in CSS beside the transitions: an
  entrance animation runs once, often from invisible, and turning that one off
  photographs nothing at all. So the elements are asked what their iteration count
  is, and the infinite ones are dropped back on the style they were animating from
  — which, for decoration, is the picture anyway. An animation declared on a
  `::before` or `::after` cannot be reached this way and is the one case left.
- **The browser's locale is pinned, because two kinds of field are not drawn by
  WordPress.** `<input type="date">` and `<input type="time">` are drawn by the
  browser, in the browser's own locale, and no amount of setting `date_format` in
  the database reaches them. So the same settings tab photographed on two machines
  reads `11/10/2026` and `04:30 PM` on one and `10/11/2026` and `16:30` on the
  other, nothing fails either time, and a set has already shipped carrying the
  capture machine's idea of a date rather than the shop's. The driver runs Chrome
  with `LC_ALL` and `LANG` set to `en_US.UTF-8`. It is not `--lang`, which is the
  obvious fix and changes nothing: the control asks ICU for the default locale and
  ICU reads the environment, so `--lang=en-GB` and `--lang=de` come back byte for
  byte identical to `--lang=en-US`.

The one thing none of that can fix is a *different shop*, which is the next
section.

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

### The shim signs a browser in, and must stay in the container

`scripts/screenshot.sh` writes a must-use plugin into the WordPress volume with a
token generated for that run. On a request carrying that token, it **signs a real
browser in as any user named on the URL** — it calls `wp_set_auth_cookie()`, so a
session token is written into that user's session list and the two cookies
WordPress sends after a successful log-in go back in the response. It is a
password-less log-in as anybody, for anybody who knows one string.

Read that twice before doing anything with this file. It is not a filter that
makes the current request look privileged; the browser leaves with credentials
and keeps them. The token is the whole of the protection, it travels in a query
string, and there is no rate limit, no capability check, no audit and no way to
revoke what has been handed out. On a site anyone else can reach it is a total
compromise of every account on it, and the log would show a successful log-in.

That is why it lives where it does, and the arrangement is not decoration:

- It is written **into the disposable WordPress volume**, never into the plugin
  under test and never into this repository's own plugin folders.
- The token is generated per run from `/dev/urandom` and never written down.
- The driver deletes the file on exit, and the volume is thrown away in any case.
- The harness binds to `localhost`.

Do not copy `tests/helpers/screenshot-mode.php` into a plugin. Do not adapt it, or
any part of it, into anything that ships — not the sign-in, not the token check,
not the header it answers with. Do not run the capture against a site that holds
real data or is reachable from anywhere but the machine running it. The harness is
the right home for this precisely because the harness is thrown away, and nothing
about the file is safe once it is somewhere that is not.

The shim signs the *browser* in and not merely the render, and that is the point of
it rather than an excess. Putting a generated cookie into `$_COOKIE` authenticates
only the request in flight, which is enough for `auth_redirect()` and leaves the
browser anonymous — so the page renders signed in and everything it then loads for
itself arrives with no session, and a nonce minted for a signed-in user is refused
when it is sent without that user's cookie. `$_COOKIE` is still filled, from the
same values, because `auth_redirect()` runs long before a cookie could come back
from the browser.

It signs a browser in **once**, and not once per request, which is the same defect
one turn further on. Every call mints a new session token, and every nonce is bound
to the token in the cookie that printed it, so a browser handed a new session on
every request has each form it submits checked against a token that did not exist
when the form was drawn. Nothing says so. The POST is refused and the screen
answering it draws as though nothing had been asked — which is why a refused nonce
is now a refused shot.

### Three traps that look like broken code

Each of these cost real time, none of them logs anything, and all three look
like a fault in the plugin or a broken install.

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

**WooCommerce sends its first wp-admin request to its own setup wizard.** On a
shop nobody has opened, the first wp-admin request anybody makes is the camera's,
so the screen the shot was pointed at answers 302 and the run fails for a frame
it could not find — which reads as a wrong selector in the shot list.
`seed_open_the_storefront()` clears it, and a seed that does not use the helper
needs both of these, because WooCommerce has kept the flag in a transient and in
an option at different versions:

```php
delete_transient( '_wc_activation_redirect' );
delete_option( '_wc_activation_redirect' );
```

**The cart a seed builds is not the cart the browser finds.** `wc_load_cart()`
under WP-CLI mints a guest session token rather than reading the user the seed
signed in as, so everything written through the session handler lands under a
key that customer's browser will never look at.

The basket survives anyway, and that is what makes this expensive rather than
obvious: WooCommerce keeps a persistent copy against the account and restores it
at sign-in, so the products, the quantities and the totals are all right in the
picture. Only what lives *solely* in the session is gone. The chosen shipping
method is the one that matters — WooCommerce picks again, so a plugin that says
something about delivery, or that treats one method differently from another,
photographs a page that drew perfectly and has nothing on it. It is the same
shape as the Coming soon page one step further in: a file of the expected size,
nothing logged, and a subject that is simply absent.

What it picks is **not the cheapest rate**, and that guess is worth getting out
of the way because it is why this survives being looked at.
`wc_get_default_shipping_method_for_package()` takes the **first rate the zone
offers** — which is the order the methods were added to it. Collection is skipped
in that walk only when the cart says it was built by a page WooCommerce
recognises; a cart a seed built reports its context as `shortcode`, and on that
branch the literal first rate is taken, collection included. Both readings are
the zone's own order, so a seed that adds free shipping before its flat rate
gets free shipping in the picture whatever it asked for, *and* gets it for the
basket that qualifies and not for the one that does not, which is
indistinguishable from the seed having worked. Reorder the two lines that build
the zone and the same shot list charges postage under a bar announcing free
delivery.

`seed_hand_the_cart_to( $customer_id )` writes the session row against the
customer, after the cart is filled and the totals are worked out. A seed that
does not use the helper needs the same write of its own:

```php
$wpdb->replace(
    $wpdb->prefix . 'woocommerce_sessions',
    array(
        'session_key'    => (string) $customer_id,
        'session_value'  => maybe_serialize( WC()->session->get_session_data() ),
        'session_expiry' => time() + 2 * DAY_IN_SECONDS,
    )
);
```

It is also what makes such a shot reproduce, which is the part that hides the
fault for longest. Left to WooCommerce the method depends on the order the zone
was built in, and a session row written by an earlier run is read in
preference to anything this one did — so a set can come back byte for byte
identical twice over and still be of a state no seed ever asked for.

Nor does that row stay wrong in the same way, because what it names is
renumbered. A chosen method is stored as a kind and an instance — `flat_rate:7`
— and the instance id is minted when the method is added to a zone, so a shop
rebuilt from empty gives the same van a different number. While the numbers
still match, every run agrees with the first and all of them are wrong together.
Once the zones are rebuilt the row names a rate the shop no longer has,
WooCommerce falls back to choosing for itself, and the same shot list produces a
different picture with nothing in the code having changed. That is what turns a
reliably wrong picture into an occasionally wrong one, and an occasionally wrong
picture is the one that gets past being looked at.

So the only reproduction check that means anything here starts from an empty
shop in a fresh container. Re-running a capture against the shop that is already
there compares the leftover row with itself, and will report byte-for-byte
agreement however wrong the subject of the picture is.

#### Four rules for a seed that chooses a delivery method

Pinning a method turns out to need four things, none of which announces itself
when it is missing. Two are now done for you inside the helpers; two are the
seed's own and cannot be.

**Start the cart as the customer, before filling it.** `seed_start_a_cart_for(
$customer_id )` signs the customer in and throws the session away so WooCommerce
builds a new one. `wc_load_cart()` alone does not do this: `initialize_session()`
builds only when there is nothing there already, so a second call hands back the
session the process is still holding. A seed that photographs two customers
otherwise fills one basket, hands it over, fills "another", and writes the first
customer's basket under the second customer's id. Which customer a session
belongs to is decided once, when it is built, by asking who is signed in at that
moment — signing in afterwards is too late and nothing says so.

`seed_hand_the_cart_to()` checks this and names both customers if they disagree.
It cannot repair it, because by then the cart has been filled against the wrong
session. It says nothing about a **guest** session, because that is not the
fault it looks like: under WP-CLI `wc_load_cart()` mints a guest token whoever is
signed in, so a seed with one customer in it has one by definition, and writing
the row under that customer's own id is the repair. Saying otherwise accused two
working seeds of the defect, which is worse than not checking, because the next
reader fixes the seed.

**Do not discard the cart.** `seed_start_a_cart_for()` rebuilds the session and
the customer and keeps the cart, and that is not tidiness. `WC_Cart_Session`
hooks `set_session()` on `woocommerce_after_calculate_totals` when a cart is
built and nothing unhooks it when that cart is thrown away, so a second cart
joins the first rather than replacing it — and the abandoned one wraps a cart
with nothing in it. `set_session()` nulls all three of the keys below whenever
the cart it holds has nothing shippable, so the next `calculate_totals()` wipes
the chosen method however carefully it was pinned. A cart already exists by the
time a WP-CLI script runs, so this is not a corner case; it is what happens every
time. Measured on WooCommerce 11.1.2, one shop, one variable: keeping the cart
leaves the pinned rate in place, discarding it leaves no stored choice at all.

**Pin where the totals will agree with the pin.**
`wc_get_chosen_shipping_method_for_package()` keeps a stored choice only when
four things hold at once: something is stored, the rate is still on offer,
`previous_shipping_methods` names the same rates the package now has, and
`shipping_method_counts` agrees on how many. The last two are what a seed has to
earn, because a session that has never served a page load has neither. Two shapes
earn them and both are in use: pin **after** the last `calculate_totals()`, so
nothing asks again; or pin after a `calculate_shipping()` and before the totals,
because that call writes both keys from the rates as they now stand. What does
not survive is a pin written into a session where no rates have been worked out.

A lost pin leaves a session indistinguishable from one the seed never pinned, so
nothing can tell the two apart afterwards and nothing tries:
`seed_hand_the_cart_to()` prints the method the photograph is going to use and
whether anything is holding it there. That line is the check, and it is worth
reading.

**Three session keys are needed, not one — and this part is done for you.**
`chosen_shipping_methods` on its own is discarded before it is read, because
`previous_shipping_methods` and `shipping_method_counts` are how WooCommerce
notices that a shop changed underneath a customer who had already chosen, and an
absent key reads as "everything differs". `seed_settle_the_delivery_method()`
writes both from the packages actually on offer, and
`seed_hand_the_cart_to()` calls it. It also refuses quietly-wrong input out
loud: a stored rate that is not among the rates the cart is offered earns a
message naming what is, because a rate id is minted when the method is added to
a zone and a rebuilt shop gives the same van a different number.

### A fourth that does not look like anything at all

The three above cost time because they look like a fault. This one costs more
because it looks like a success: the page draws completely, the run saves, the
file is the size you expected, and the photograph is of the **free edition**
with the paid one captioned underneath it.

It applies to any plugin whose paid edition runs on an install grace — a window
after installation in which the paid features work before a licence key has
been entered. Two ordinary details of how such a grace is written decide
whether a capture photographs the edition it believes it is photographing:

- **The clock has to start somewhere, and not on a shopper's page load.**
  Writing the install stamp on every front-end request until one of them
  succeeds is a database write nobody wants, so the stamp is written on the
  first **admin** request or on a cron run, and nowhere else. Until one of
  those happens there is no stamp.
- **A grace that returns whenever the stamp is missing is a grace anybody can
  have twice.** So the code usually asks a second question before handing one
  out: has this plugin run on this site before? The evidence it looks for is
  the paid plugin's own options already being in the database — which reads as
  a site whose licence key has been removed, not as a fresh install, and the
  grace is refused rather than granted.

A seed meets both of those in the worst possible order. It writes the paid
edition's options directly, through WP-CLI, which is neither an admin request
nor cron. So no stamp is written, the options are there to be found, and the
plugin concludes it is running unlicensed on a site that has had its key taken
away. Every paid feature switches itself off, and the storefront draws the free
edition while the paid plugin sits there installed and active.

Nothing here catches that. Every refusal this harness makes is about a page
that failed to draw — an asset that did not arrive, a frame that does not close
on all four sides, a request that came back an error, a subject that moved
after it was measured — and this page did not fail to draw. It is a complete,
correct, reproducible photograph of the wrong product, and only a reader who
already knows what the paid edition looks like can tell.

**What makes a set safe, and it is structural rather than lucky.** The whole
shot list is warmed before the first shutter opens, not each shot before
itself. So a single `wp-admin` path anywhere in the list — first line or last —
writes the install stamp while warming, and every shot in the set, storefront
ones included, is then of the licensed edition. Most published sets are mostly
wp-admin screens, so most sets are safe without anyone having arranged it.

**What makes one exposed is a shot list of storefront paths only.** That is an
easy list to write, because the storefront is the half a customer sees and the
half worth showing: a product page, a category page, a cart, a checkout, and
nothing else. Such a list never makes an admin request, so the stamp is never
written and every shot in it is of the free edition.

Note that warming does not help by being done as the administrator, which it
is. `is_admin()` is decided by the path, not by who is asking for it, so a
storefront list warmed as the administrator is still a storefront list and
still writes no stamp.

**So the fix is a line of shot list rather than a change here.** Have one
`wp-admin` path in the list; where it sits does not matter, because warming has
finished before anything is photographed. The settings screen the plugin is
being sold on is usually in the set anyway, which is why this is cheaper than
any check. Where a set genuinely has no admin screen in it, the seed can write
the stamp itself — by asking the plugin's own licence code to record an
installation, or by requesting `wp-cron.php` once after seeding.

And whatever the list looks like, it is worth finding one thing in one
storefront shot that only the paid edition draws, and confirming it is there,
before a set is published. That is thirty seconds and it is the only check that
does not depend on knowing any of the above.

### A warning about the shop has to be in the picture

Published sets in this range are cropped to the plugin's own screen, so the
furniture goes before the shutter rather than being cut off after it: cropping a
2x render leaves a visible half-pixel seam where a hidden element leaves none. The
admin menu, the toolbar, the screen-options tabs, WordPress's "a new version is
available" nag, WooCommerce's store alerts and its own page header are all removed
that way, each one named by its own class.

A notice cannot be. WordPress and WooCommerce write banners across the top of
every admin screen, and the plugin being photographed writes its own warnings in
the same markup, often to the same four hooks — `admin_notices`,
`all_admin_notices`, `network_admin_notices`, `user_admin_notices`. The class is
the same. The position is the same. Neither tells you whose voice it is.

For a long time one CSS rule hid `.notice` outright, which is the tidiest possible
way to get this wrong. A shop that the plugin was warning about — a setting that
contradicted its own shipping zones, a rule naming a delivery method that had been
deleted — photographed exactly like a shop with nothing to say. No gap, no error,
nothing refused, and no way afterwards to tell that picture from one of a screen
that had been quiet. A caption can then contradict its own subject for as long as
anybody cares to look at it.

What does tell the two apart is **where the callback was defined**. A notice
registered by a file under `wp-admin/`, under `wp-includes/` or inside the
`woocommerce` plugin folder is furniture. Anything else is the plugin under the
camera. So the hooks are read at `admin_init` priority 99, every callback is
sorted on that question, and the furniture is dropped.

The rest are not reinstated, and that is deliberate: a banner put back at the top
of the page would move every subject in every existing shot list down by its own
height. They are run into an output buffer which is thrown away — and then the
buffer is read. If what it held was dressed as a warning or an error, the shot is
**refused**, and the sentence is printed across the top of the rejected render.

Three things follow, and together they are the guarantee:

- A warning the plugin draws **inside its own screen** appears in the picture,
  because nothing hides it any more. If it falls outside the frame the shot is
  refused rather than cropped past it, so it cannot be silently trimmed off.
- A warning that arrives **on one of the four hooks** is not drawn, but is not
  lost either: it refuses the shot and says what it said.
- So a shop that is being warned about something cannot be photographed clean.
  Either the warning is in the picture or there is no picture.

What that does **not** cover, which is the part worth knowing before trusting it:

- **Severity is read off classes it recognises** — `notice-warning`,
  `notice-error`, `woocommerce-error`, WordPress's older `notice error` pair, and
  the block editor's error and warning banners. A plugin that dresses a warning in
  a class of its own is invisible to this, and will be drawn in the picture but
  will not refuse a shot that leaves it out of frame.
- **Information and success are still removed silently**, and on purpose.
  "Settings saved." is on very nearly every admin screen a capture visits, and a
  check that refused those is a check somebody switches off within the week. The
  cost is real and it is accepted: an info notice that mattered goes unremarked.
- **It cannot tell a warning about the shop from a warning about the plugin.** It
  refuses either, which errs the safe way but means a message about something the
  picture does not claim anything about can still stop a run. Read the sentence,
  then either widen the frame or put the shop right.
- **Provenance is a file path**, so the two ways to fool it are a plugin whose
  notices are registered from code living inside the WooCommerce folder, and a
  WordPress or WooCommerce notice registered later than `admin_init` 99. Neither
  has been met; both would read as the opposite of what they are.
- `pc_chrome=on` turns the whole furniture rule off, banners included. That is a
  picture of the entire admin screen and a different job from a cropped one.

Everything else this shim takes out of a subject is here, so the question has one
place to be answered. Transitions are disabled, which lands an element on the
style it was moving from; an animation that never ends is stopped, which lands one
on the style it was drawn with; the admin bar is switched off; and WooCommerce's
helper notices are suppressed by its own filter. Lazy loading is switched off too,
but that is the opposite — it puts an image into the picture that would otherwise
have arrived after it.

### What cannot be photographed

Whoever writes the captions needs to know what this will not do, because a caption
is a promise and the gap between the two is only ever found by a reader. The list
is short and each line has been tried rather than assumed.

Things that are often assumed to be out of reach and are not: a screen behind a
log-in, including the storefront as a named customer; a screen that draws itself
over admin-ajax, the REST API or the Store API; the block editor, which is REST
and nonces throughout; a WooCommerce transactional email, through WooCommerce's
own preview on the email settings screen, which a seed can point at a real order
with the `woocommerce_email_preview_dummy_order` filter; a panel that has nothing
on it until a form has been filled in and submitted, which the `click` column
does; and the whole admin screen with its menu, its toolbar and the banners
WordPress and WooCommerce write across the top of it, by putting `pc_chrome=on` in
the shot's own path. What follows is what is left.

- **A hover or a focus state.** There is a `click` and there is nothing else: the
  render has no pointer and no keyboard, so `:hover` never matches. A tooltip, a
  menu that opens on hover and a focus ring cannot be photographed, and there is
  no way to ask for one from a shot list.
- **A control the operating system draws.** An open `<select>`, the browser's own
  date picker, the colour picker: those are painted outside the page and are not
  in a picture of the page at all. A drop-down built out of HTML is fine and opens
  with `click`.
- **A form's answer that arrives as a redirect rather than as a page.** A
  sequence of steps can submit a form and photograph what comes back, but only
  where the answer *is* the response: a screen that saves and then redirects gives
  the browser a fresh page load, and nothing can tell that apart from a form that
  was never submitted, so it is refused. Where the redirect lands on a URL of its
  own — `?settings-updated=true` and its like — ask for that URL instead, and it
  photographs normally. What stays genuinely out of reach is anything the answer
  to a form cannot be reached without doing for real: an order-received page needs
  a payment.
- **Anything outside wp-admin and the theme.** `wp-login.php` and the like draw
  their own pages and fire none of the hooks the frame is printed on, so the
  wrong-password message on a log-in form is unreachable however it is asked for.
- **Anything that appears on scroll.** Chrome photographs the viewport, so the
  render never scrolls: a sticky header in its stuck state, or a section that
  reveals itself part way down, is not reachable. Widen or heighten the viewport
  instead of trying to scroll to a subject; a rule with an edge off screen stops
  the run rather than cropping to the part that was visible.
- **A subject the viewport holds in place rather than the page.** Anything
  `position: fixed` cannot be framed, and the reason is the rule rather than the
  subject, which is why no `frame`, `pad` or viewport size gets round it. The rule
  is an absolutely positioned element put at the subject's *document* coordinates;
  a fixed element is laid out against the viewport instead, so the two only agree
  where the page has not scrolled and nothing has offset the body. Two worked
  cases, both refused. A notification bar pinned to the bottom of a narrow
  viewport: the picture shows the bar drawn correctly at the foot of the page and
  the rule about seventy page pixels above it. A cart drawer pinned to the right:
  a fixed element stretched `left: 0; right: 0` is the full width of the viewport,
  so there is no room for a rule beside it at any `pad`, and that half needs no
  arithmetic at all. Both come back as `the rule in … has no right edge, so the
  subject is bigger than the viewport it was rendered in: raise the width or the
  height for this shot` — true of the rule and misleading about the cure, because
  raising either is the one thing that cannot help. **This one stops the run**,
  which is the kind to want: nothing is saved, so no set quietly gains a picture
  of a rule round the wrong part of a page. A fixed element does sometimes
  photograph, and that is luck worth recognising rather than support: one pinned to
  the top of a page that has not scrolled sits where its document coordinates say
  it does, so a bar above the theme's own header frames normally while the same bar
  moved to the bottom will not.
- **A card form.** The fields belong to the payment gateway, are drawn from its
  servers, and want its keys. Nothing here has any and nothing should be given
  any. A checkout *is* photographable — cheque and cash on delivery draw
  normally — but the moment a real gateway is in the picture, it is not.
- **Anything whose content comes from somebody else's server**, which is worse
  than unphotographable because it looks fine. It will usually render, since the
  machine has a route out, but what is in the picture is whatever that server said
  today, so the shot does not reproduce. Worse, the request check deliberately
  ignores cross-origin requests — a page reaching a third party is not the page
  drawing itself, and in a container with no route out every such request would
  fail — so a third party that answers with an error does **not** refuse the shot.
  Treat any screen with an embed in it as unchecked, and look at it.
- **A pseudo-element's endless animation.** The infinite animations are stopped
  before the shutter opens, but only on elements; one declared on a `::before` or
  `::after` cannot be reached, and a shot containing one will not reproduce byte
  for byte.
- **A screen whose second step has to wait for what the first one started.** The
  steps in a `click` column are taken on the load event, in one pass, with no
  pause between them, so a step cannot wait for a request an earlier step set in
  motion. WooCommerce's Variations panel is the case: the tab is clicked, the
  rows are fetched over admin-ajax, and the Expand link in the toolbar beside
  them is clicked before any row exists. The click *succeeds* — the toolbar was
  rendered with the page — and expands an empty list, so the panel photographs
  with its rows collapsed and nothing is refused, because every selector
  matched. Aim a step at a row instead and the refusal says it plainly: `step 2
  of 2 did not happen: nothing on this page matches
  ".woocommerce_variation:first-child .handlediv"`. A sequence can fill in a
  form, because a form is on the page already; it cannot work through a screen
  that builds itself a piece at a time.

Three of those are worth saying again because they are the ones that produce a
file rather than an error: a third-party embed, a pseudo-element animation, and a
step that clicked something real and achieved nothing. A green run is evidence
that the pages loaded and the crops are in the right place. It is not evidence
that the pictures show what a caption says they show, and nothing here can be.

### Driving the containers

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

**And clear those variables before driving a second checkout from the same
shell.** `HARNESS_ROOT` and `COMPOSE_PROJECT_NAME` are honoured from the
environment if they are already set, and both are exported, so a shell that has
sourced `lib.sh` once carries the first checkout's values into everything it runs
afterwards. Clone this repo somewhere else, run its scripts from that same shell,
and they drive the first checkout's containers with the first plugin mounted. The
symptom is `pc_compose ps -q wordpress` coming back empty, or an install that
reports success against a stack you are not looking at. `unset HARNESS_ROOT
COMPOSE_PROJECT_NAME` first, or use a new shell.

**Swap a plugin's *contents*, never the directory itself.** `PLUGIN_PATH` is bind
mounted into the container, and a bind mount is resolved once, to an inode. Delete
the directory and put another one back under the same name — which is what
`rm -rf` then `cp -r` does, and the obvious way to photograph a second edition
without restarting anything — and the mount still points at the inode that was
unlinked. The container then sees an empty plugin folder while the host shows a
full one.

Nothing about the symptom says any of that. WordPress deactivates the plugin it
can no longer find, the capture signs in, wp-admin answers **"Sorry, you are not
allowed to access this page."** because the settings page it is asking for is not
registered any more, and the shot is refused for a frame that matched nothing.
The refusal names the selector, which is the honest thing for it to say and
points at the wrong culprit here: the selector is right and the screen is not.
The two plausible explanations — a broken login shim and a wrong selector — are
both wrong, and both take a while to rule out. Replace the contents instead:

```bash
find "$PLUGIN_PATH" -mindepth 1 -delete
cp -r /path/to/other-edition/. "$PLUGIN_PATH"/
```

If it has already happened, `./scripts/stop.sh` and `./scripts/start.sh` rebind
the mount. The rejected render the capture leaves behind is what names it: it is a
picture of the "not allowed" page rather than of a plugin screen.

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

## Two failures that are the harness and not the plugin

The traps that only bite a capture are under
[Three traps that look like broken code](#three-traps-that-look-like-broken-code).
These two bite any run, and both have already been read as a fault in the plugin.

**A registry failure can still arrive wearing something else's clothes.** The
retry above covers one thing: fetching an image the machine has not got, before
anything starts. Four registry problems are still waiting on the other side of
it, and none of them says "registry" anywhere in the failure.

- **A pull quota is retried and still fails.** `toomanyrequests` cannot be told
  apart from a transport failure here, so it takes all three attempts and is then
  reported as three attempts. A retry cannot mint quota; what it buys is a
  failure that names the registry rather than looking like a broken image.
- **WordPress and WooCommerce do not come from the registry.** `install.sh`
  downloads them from wordpress.org, inside the container, over a connection this
  has nothing to do with, and nothing retries that. A drop shows up as an install
  step failing — or, worse, as WooCommerce simply not being there afterwards, so
  the plugin's own tests fail on everything WooCommerce would have provided. A
  run whose plugin tests fail wholesale is worth checking against the install
  output above them before it is read as a regression.
- **An image the machine already has is never refreshed.** That is deliberate,
  and it is what `up` did, but it means a stale layer under a moving tag such as
  `mariadb:11` stays until somebody removes it. The symptom is a version that
  does not match the one CI installed. `docker image rm` the tag and run again.
- **Compose too old to answer `config --images`** leaves the fetch to `up`,
  unretried, and says so in one line. The failure is then the original one: a
  Compose error about a manifest, with nothing to say that no code has run.

**Skipping the generic tests can change what the plugin tests find.**
`PC_SKIP_GENERIC_TESTS=1` is the obvious economy when the plugin's own suite is
the one being iterated on, and it is not free: the generic tests are the only
part of a run that loads wp-admin over HTTP, and a plugin does work on an admin
request that it does not do under WP-CLI.

This range has one instance that costs an afternoon. A paid build starts its
licence grace clock on the first admin or cron request, because a plugin replaced
by upload never sees an activation hook and locking that shop out would be worse
than trusting it. Under `wp eval-file` neither `is_admin()` nor `wp_doing_cron()`
is true, so the clock is never started — while activation *has* seeded the
plugin's own options, which the same code reads as evidence that the paid build
has run here before. The grace therefore reads as spent, the licence reads as
lapsed, and every assertion about a paid feature fails: twenty-three of them in
one plugin, in a run where nothing was wrong.

It appears and disappears on that one flag, on the same machine and the same
commit, with the same plugin mounted:

```bash
PLUGIN_PATH=... PLUGIN_SLUG=... ./scripts/run-tests.sh
# 121 passed, 0 failed

PC_SKIP_GENERIC_TESTS=1 PLUGIN_PATH=... PLUGIN_SLUG=... ./scripts/run-tests.sh
# 23 failed, from the first assertion about the licence onward
```

CI never sets the flag, which is why a failure like this reads as a local machine
problem — the same commit is green on a runner and red here. It is not the
machine. Before believing that a run differs from CI, run it the way CI does.

## Limitations

- Docker is required. There is no native WP-CLI fallback in this harness
- Official `wordpress:VERSION-phpX.Y-apache` tags do not exist for every pair
- `wordpress:cli-phpX.Y` must exist for the chosen PHP version
- Generic tests talk to the WordPress container as `http://wordpress` (Compose network name). The host browser uses `http://localhost:8080`
- HPOS is toggled with WooCommerce options. Very old WooCommerce versions may ignore those options
- Plugin tests that need Composer packages must vendor them in the plugin; the WP-CLI image does not install plugin `vendor/` for you
