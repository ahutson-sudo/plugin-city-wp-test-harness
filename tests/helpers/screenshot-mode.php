<?php
/**
 * Plugin Name: PluginCity screenshot mode
 * Description: Signs a headless browser into the site, strips the furniture, marks the subject of each shot so it can be cropped exactly, and refuses the frame when the page did not finish drawing itself. Installed into the harness's disposable WordPress volume by scripts/screenshot.sh.
 *
 * @package PluginCityHarness
 *
 * This file is copied into wp-content/mu-plugins by the screenshot driver with
 * its token substituted. It is deliberately not part of any plugin: on request
 * it signs a browser in as any user on the site, which belongs only inside a
 * throwaway container.
 *
 * Three things here are not obvious and each of them cost an afternoon.
 *
 * Filtering determine_current_user is not enough. wp-admin/admin.php calls
 * auth_redirect(), which asks wp_validate_auth_cookie() directly and never
 * consults that filter, so every admin screen bounces to wp-login.php. Putting
 * a genuine wp_generate_auth_cookie() value into $_COOKIE does work.
 *
 * $_COOKIE alone is not enough either, and that is the harder half. It signs
 * the *server* in for the request being rendered and leaves the browser
 * anonymous, so every request the page then makes for itself -- admin-ajax, the
 * REST API, WooCommerce's Store API -- arrives with no session, and a nonce
 * minted for a signed-in user is not valid when it is sent without that user's
 * cookie. The browser therefore gets real Set-Cookie headers as well, and
 * $_COOKIE is filled from the same values so that one session token covers the
 * page and everything it asks for. See pc_shot_sign_in().
 *
 * And signing in on *every* request is not enough either, which is the third of
 * them and the quietest. See pc_shot_sign_in() again: a session is minted once
 * per browser, not once per request.
 *
 * It has to happen on plugins_loaded rather than at file scope, because
 * wp-settings.php loads must-use plugins *before* wp_cookie_constants(), so
 * reading LOGGED_IN_COOKIE any earlier is a fatal error on every request.
 */

defined( 'ABSPATH' ) || exit;

const PC_SHOT_TOKEN = 'REPLACE_TOKEN';

/**
 * Who a shot is taken as when its path does not say otherwise.
 */
const PC_SHOT_USER = 'admin';

/**
 * What a shot list writes instead of a login to be photographed signed out.
 */
const PC_SHOT_NOBODY = 'visitor';

/**
 * The colours the rule round the subject may be drawn in.
 *
 * There is one render and no channel back out of it, so the verdict on whether
 * the page finished drawing itself travels as the colour of the rule.
 * scripts/crop-to-frame.py holds the same table and is the only thing that
 * reads it: magenta crops, and each of the other five stops the run and names a
 * different thing to go and fix. Keep the two lists in step.
 *
 * All six are colours nothing in wp-admin, in a block theme or in WooCommerce
 * draws, which is the only property they need.
 */
const PC_SHOT_RULE = array(
	'ok'      => '#ff00ff',
	'failed'  => '#00ff00',
	'pending' => '#00ffff',
	'moved'   => '#ffff00',
	'stale'   => '#ff0000',
	'undone'  => '#0000ff',
);

add_action(
	'plugins_loaded',
	static function (): void {
		// phpcs:disable WordPress.Security.NonceVerification.Recommended
		if ( ! isset( $_GET['pc_shot'] ) || ! hash_equals( PC_SHOT_TOKEN, (string) $_GET['pc_shot'] ) ) {
			return;
		}

		$viewer = isset( $_GET['pc_as'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['pc_as'] ) ) : PC_SHOT_USER;

		// The driver reads both of these off the warm-up request with curl,
		// which is the one moment in a capture when something other than a
		// browser is looking. A shot list asking to be photographed as somebody
		// the shop has never heard of is a wrong picture waiting to happen --
		// signed out where it meant to be signed in -- and the answer to it is
		// a header, because a picture cannot carry the reason.
		if ( PC_SHOT_NOBODY === $viewer ) {
			header( 'X-Pc-Shot-Viewer: ' . PC_SHOT_NOBODY );
		} else {
			$user = get_user_by( 'login', $viewer );

			if ( ! $user ) {
				header( 'X-Pc-Shot-Error: no user called ' . $viewer );
				return;
			}

			pc_shot_sign_in( $user );
			header( 'X-Pc-Shot-Viewer: ' . $user->user_login );
			// Named rather than assumed, so the driver can require that this
			// same response really did set it. A site can rename the cookie.
			header( 'X-Pc-Shot-Session: ' . LOGGED_IN_COOKIE );
		}

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

		// A photograph must not depend on when the browser got round to an
		// image. WordPress serves them decoding="async" and lazily below the
		// fold, and Chrome will paint a frame before either has finished, so a
		// product page came back with an empty image column on one run in two
		// -- the same shot list, the same shop, nothing failing, and the only
		// thing that noticed was comparing the two sets byte for byte.
		//
		// Both filters are here rather than in the browser because the tag has
		// to be right in the HTML: an attribute corrected by script afterwards
		// is corrected after the decision it was going to change.
		add_filter( 'wp_lazy_loading_enabled', '__return_false' );
		add_filter(
			'wp_get_attachment_image_attributes',
			static function ( $attr ) {
				$attr['loading']  = 'eager';
				$attr['decoding'] = 'sync';

				return $attr;
			}
		);

		if ( ! isset( $_GET['pc_chrome'] ) || 'on' !== $_GET['pc_chrome'] ) {
			add_action( 'admin_head', 'pc_shot_strip_furniture', 999 );
			add_action( 'wp_head', 'pc_shot_strip_furniture', 999 );
		}

		$click = isset( $_GET['pc_click'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['pc_click'] ) ) : '';
		$frame = isset( $_GET['pc_frame'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['pc_frame'] ) ) : '';
		$pad   = isset( $_GET['pc_pad'] ) ? absint( $_GET['pc_pad'] ) : 0;

		$allow = array();
		if ( isset( $_GET['pc_allow'] ) && is_array( $_GET['pc_allow'] ) ) {
			foreach ( wp_unslash( $_GET['pc_allow'] ) as $one ) {
				$one = sanitize_text_field( (string) $one );
				if ( '' !== $one ) {
					$allow[] = $one;
				}
			}
		}
		// phpcs:enable WordPress.Security.NonceVerification.Recommended

		if ( '' === $click && '' === $frame ) {
			return;
		}

		if ( '' !== $frame ) {
			// Before any script the page enqueues, because it counts the
			// requests they make. print_head_scripts runs on
			// admin_print_scripts at 20 and on wp_head at 9.
			$watcher = static function () use ( $allow ): void {
				pc_shot_print_watcher( $allow );
			};

			add_action( 'admin_print_scripts', $watcher, 1 );
			add_action( 'wp_head', $watcher, 0 );
		}

		$posted = isset( $_SERVER['REQUEST_METHOD'] )
			&& 'POST' === strtoupper( sanitize_text_field( wp_unslash( (string) $_SERVER['REQUEST_METHOD'] ) ) );

		$script = static function () use ( $click, $frame, $pad, $posted ): void {
			pc_shot_print_script( $click, $frame, $pad, $posted );
		};

		add_action( 'admin_footer', $script, 999 );
		add_action( 'wp_footer', $script, 999 );
	},
	0
);

/**
 * Sign this request in, and sign the browser in with it.
 *
 * wp_set_auth_cookie() is the whole of the mechanism: it mints a session token,
 * writes it into the user's session list, and sends the two cookies WordPress
 * itself sends after a successful log-in. The two actions copy those exact
 * values into $_COOKIE, which is what the request in flight is validated
 * against -- auth_redirect() runs long before a cookie could come back from the
 * browser, so the page could not otherwise render at all.
 *
 * Taking the values off the actions rather than generating a second pair
 * matters: a nonce printed on the page is bound to the session token in the
 * cookie that printed it, so the page and the requests it makes have to be
 * carrying the same token or every nonce on the screen is refused.
 *
 * Which is also why a browser that is already signed in is left alone. Every
 * call mints a *new* session token, and this runs before anything verifies a
 * nonce, so signing in unconditionally means a form drawn on one request has its
 * nonce checked against a token that did not exist when it was printed. Nothing
 * says so: the POST is refused, and the screen answering it draws as though
 * nothing had been asked -- which photographs perfectly well. The check is made
 * on the logged-in cookie because that is the one every nonce is bound to, and
 * on a wp-admin request the browser sends the auth cookie beside it or the
 * screen would not have rendered at all.
 *
 * Nothing here sets SameSite, which leaves Chrome's default of Lax. Every
 * request a shot makes is to the same origin as the page, so Lax sends the
 * cookie; and the cookies are not marked secure, because the harness is served
 * over http and a secure cookie would simply be dropped.
 *
 * The alternative was writing Chrome's cookie jar before it starts, or driving
 * it over the DevTools protocol to set cookies directly. Both mean knowing more
 * about the browser than the harness should have to: the jar is an encrypted
 * SQLite schema that moves between Chrome releases, and the protocol means
 * giving up one-shot --screenshot rendering for a websocket client and a
 * dependency to install. A Set-Cookie header is the browser's own documented
 * way in and needs nothing.
 *
 * @param WP_User $user The user to be photographed as.
 */
function pc_shot_sign_in( WP_User $user ): void {
	$held = isset( $_COOKIE[ LOGGED_IN_COOKIE ] ) ? (string) $_COOKIE[ LOGGED_IN_COOKIE ] : '';

	if ( '' !== $held && (int) $user->ID === (int) wp_validate_auth_cookie( $held, 'logged_in' ) ) {
		return;
	}

	add_action(
		'set_auth_cookie',
		static function ( $cookie, $expire, $expiration, $user_id, $scheme ): void {
			$_COOKIE[ 'secure_auth' === $scheme ? SECURE_AUTH_COOKIE : AUTH_COOKIE ] = $cookie;
		},
		10,
		5
	);

	add_action(
		'set_logged_in_cookie',
		static function ( $cookie ): void {
			$_COOKIE[ LOGGED_IN_COOKIE ] = $cookie;
		}
	);

	// Not remembered, and not secure: a session cookie is right because each
	// shot gets a fresh browser profile, and the secure flag is asked for
	// explicitly rather than left to is_ssl() so that a shop whose home option
	// says https cannot end up sending a cookie the browser throws away.
	wp_set_auth_cookie( $user->ID, false, false );
}

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
		/* A transition is a picture with no single right moment in it. The
		   variable product page fades its gallery when a variation is chosen,
		   which is one class change and then four hundred milliseconds of the
		   browser redrawing without touching the document, so waiting for the
		   page to go quiet does not wait for this. One run in two came back
		   with the product photograph half faded.

		   Transitions are turned off rather than shortened, which lands every
		   element on the value it was transitioning to. Animations are left
		   alone on purpose: an element whose base style is invisible and whose
		   keyframes bring it in would be photographed invisible. */
		*, *::before, *::after { transition: none !important; }
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
 * Count what the page fetches for itself, and remember anything that went wrong.
 *
 * A screen that draws its own content over admin-ajax, the REST API or the
 * Store API is the one that photographs wrongly without looking wrong: the
 * request is refused, the region either stays empty or grows an error banner,
 * and the file saves at a plausible size. This is how the frame comes to know,
 * so that it can refuse to be cropped.
 *
 * What it asserts is positive. Not "no error text on the page", which only ever
 * catches the failures somebody had already thought of, but: every request this
 * page made in order to draw itself finished, and answered. Requests to other
 * origins are left out, because a page reaching a third party is not the page
 * drawing itself -- and in a container with no route to one, every such request
 * fails whether or not anything is wrong.
 *
 * $excuse is the shot list's list of requests that are known to fail and known
 * not to change the screen; see the allow lines in scripts/screenshot.sh. A
 * request matching one is not watched at all rather than watched and forgiven,
 * because some of them retry for as long as the page is open and would
 * otherwise be in flight at the moment the subject is measured. Each one has to
 * match something: an excuse that no longer describes the page is a hole in
 * this check nobody knows is there, so the rule comes out stale and the run
 * stops.
 *
 * @param string[] $excuse URL fragments this shot has been told to ignore.
 */
function pc_shot_print_watcher( array $excuse = array() ): void {
	printf(
		'<script id="pc-shot-watch">(function(){
		var excuse=%1$s, used={};
		var w={inflight:0,asked:0,failed:[],excuse:excuse,used:used};
		window.pcShotWatch=w;
		function watch(u){
			var full;
			try{ full=new URL(u,location.href); }catch(e){ return false; }
			if(full.origin!==location.origin){ return false; }
			for(var i=0;i<excuse.length;i++){
				if(u.indexOf(excuse[i])>=0||full.href.indexOf(excuse[i])>=0){
					used[excuse[i]]=(used[excuse[i]]||0)+1;
					return false;
				}
			}
			return true;
		}
		function bad(m){ if(w.failed.indexOf(m)<0){ w.failed.push(m); } }
		var fetched=window.fetch;
		if(fetched){
			window.fetch=function(input){
				var u=(typeof input==="string")?input:((input&&input.url)||"");
				if(!watch(u)){ return fetched.apply(this,arguments); }
				w.inflight++; w.asked++;
				return fetched.apply(this,arguments).then(function(r){
					w.inflight--;
					if(!r.ok){ bad("HTTP "+r.status+" from "+u); }
					return r;
				},function(e){ w.inflight--; bad("no answer from "+u); throw e; });
			};
		}
		var open=XMLHttpRequest.prototype.open, send=XMLHttpRequest.prototype.send;
		XMLHttpRequest.prototype.open=function(m,u){ this.pcShotUrl=u; return open.apply(this,arguments); };
		XMLHttpRequest.prototype.send=function(){
			var x=this, u=x.pcShotUrl||"";
			if(!watch(u)){ return send.apply(this,arguments); }
			w.inflight++; w.asked++;
			var counted=false;
			function settle(){ if(counted){ return false; } counted=true; w.inflight--; return true; }
			x.addEventListener("load",function(){
				if(!settle()){ return; }
				if(x.status<200||x.status>=300){ bad("HTTP "+x.status+" from "+u); }
			});
			x.addEventListener("error",function(){ if(settle()){ bad("no answer from "+u); } });
			x.addEventListener("timeout",function(){ if(settle()){ bad("no answer in time from "+u); } });
			x.addEventListener("abort",function(){ if(settle()){ bad("given up before it answered: "+u); } });
			return send.apply(this,arguments);
		};
	})();</script>',
		wp_json_encode( array_values( $excuse ) )
	);
}

/**
 * Read pc_click as the sequence of things to do before the picture is taken.
 *
 * One step per '|', and a step written 'selector ::= value' types the value into
 * the field rather than clicking it. Both tokens were inherited from the first
 * shot list that needed a sequence and both were kept, for opposite reasons.
 *
 * '::=' cannot be mistaken for CSS. A selector may contain a colon and may
 * contain two, but ':: =' is not a pseudo-element and nothing in the language
 * puts an equals sign after one. Everything after the first '::=' is the value,
 * rejoined, so a value may contain the token even though a selector cannot.
 *
 * '|' can be mistaken for CSS, in [lang|="en"], and a value a shop types could
 * contain one too. There is no separator that could not: this column carries
 * arbitrary strings in a file whose columns are already separated by tabs. So
 * the collision is made loud rather than legislated away -- a selector cut in
 * half either stops being a selector the browser will parse or stops matching
 * anything, and both refuse the shot and name the step. Neither is silent, which
 * is the property that matters.
 *
 * @param string $click The pc_click parameter as the shot list wrote it.
 *
 * @return array<int,array{find:string,type:string|null,said:string}>
 */
function pc_shot_steps( string $click ): array {
	$steps = array();

	if ( '' === trim( $click ) ) {
		return $steps;
	}

	foreach ( explode( '|', $click ) as $one ) {
		$one = trim( $one );
		$at  = strpos( $one, '::=' );

		if ( false === $at ) {
			$steps[] = array(
				'find' => $one,
				'type' => null,
				'said' => $one,
			);
			continue;
		}

		$steps[] = array(
			'find' => trim( substr( $one, 0, $at ) ),
			'type' => trim( substr( $one, $at + 3 ) ),
			'said' => $one,
		);
	}

	return $steps;
}

/**
 * Take the steps, wait for the page to finish, and draw the rule the cropper reads.
 *
 * pc_click exists because a tabbed metabox opens on whichever tab its own
 * script picked and a still photograph cannot click. Firing the real click
 * rather than forcing a panel visible with CSS keeps the chosen tab drawn the
 * way its own plugin draws an active one.
 *
 * A sequence exists because some screens cannot be reached by asking for a URL
 * at all. A panel that answers a form has nothing on it until the form has been
 * filled in and submitted, and a picture of the empty one is a picture of a
 * feature not working. So the steps fill it in and press the button.
 *
 * Every step has to happen, and a step that did not is a refusal rather than
 * something to carry on past. A form filled in with two of its three fields
 * photographs perfectly well, and so does a panel that was never asked anything:
 * those two pictures are the whole reason this is checked at all rather than
 * hoped for.
 *
 * The request watch below cannot see the last step, and it is worth being exact
 * about why. It counts what the page fetches for itself; submitting a form is a
 * navigation, so the POST is not a request this document ever makes -- it is the
 * reason the next document exists. What answers for it instead is $posted: the
 * steps are remembered in sessionStorage, which is the one thing that survives a
 * navigation in the same tab, so the document that comes back can tell that a
 * sequence ran, that it ran to the end, and that it itself arrived as the answer
 * to a POST. Everything that document then loads for itself is watched as usual.
 *
 * pc_frame exists because the crop is the part of this job most easily got
 * wrong by hand: a box read off a preview is out by a few pixels, and the
 * error only shows once the set is seen side by side. The page marks its own
 * subject instead, so the numbers come out of the browser's layout.
 *
 * Nothing here is timed, because no flat number is right: the answer belongs to
 * whatever scripts the page happens to run. A third of a second was not enough
 * for anything WooCommerce drives with jQuery -- a variable product's form runs
 * on wc_variation_form, which can fire after load and empties the image column
 * before refilling it, so a shot landing inside that gap photographed a product
 * page with no photograph on it, once in two runs, with nothing failing.
 *
 * So the rule waits for three things at once before it is drawn: a
 * quarter-second in which the DOM was not touched, nothing left in flight, and a
 * subject that measures the same twice running. The last two are what the
 * too-tall crop needed. A basket drawn by the Store API was measured while its
 * fetch was still out, then grew an error banner above the columns -- the rule
 * stayed where it was put and the subject moved down behind it, so the crop came
 * out the banner's height too high, saved, and looked like a screenshot.
 *
 * The verdict is the colour of the rule, and the watch carries on after the rule
 * is drawn: Chrome takes the picture when its virtual time budget runs out, not
 * when we are ready, so a request that fails afterwards, or a subject that moves
 * afterwards, would otherwise be in the photograph and in nothing else. While
 * there is patience left a subject that has moved is simply measured again; the
 * refusal is for one that is still moving when the patience runs out.
 *
 * @param string $click  Steps to take first, or ''.
 * @param string $frame  Selector list whose union is the subject, or ''.
 * @param int    $pad    Pixels of page to keep around the subject.
 * @param bool   $posted Whether this document is the answer to a POST.
 */
function pc_shot_print_script( string $click, string $frame, int $pad, bool $posted = false ): void {
	printf(
		'<script>window.addEventListener("load",function(){
			var steps=%1$s, frame=%2$s, pad=%3$d, rule=%4$s, posted=%5$s, key=%6$s;
			var report="";
			/* Where the sequence got to, kept across the navigation the last step
			   causes. A fresh browser profile per shot means nothing here is ever
			   another shot\'s. */
			var MARK="pc-shot-steps", store=null, prior=null;
			try{
				window.sessionStorage.setItem(MARK+"-probe","1");
				window.sessionStorage.removeItem(MARK+"-probe");
				store=window.sessionStorage;
				prior=JSON.parse(store.getItem(MARK)||"null");
			}catch(e){ store=null; prior=null; }
			if(prior&&prior.of!==key){ prior=null; }
			var state={of:key,at:0,done:0,click:0,why:""};
			function keep(){ if(store){ try{ store.setItem(MARK,JSON.stringify(state)); }catch(e){} } }
			function stopped(i,because){
				state.why="step "+(i+1)+" of "+steps.length+" did not happen: "+because;
				report=state.why;
				keep();
			}
			function take(){
				for(var i=0;i<steps.length;i++){
					var s=steps[i], node=null;
					state.at=i+1; keep();
					if(!s.find){ stopped(i,"there is no selector in it"); return; }
					try{ node=document.querySelector(s.find); }
					catch(e){ stopped(i,"the browser does not understand \\""+s.find+"\\" as a selector"); return; }
					if(!node){ stopped(i,"nothing on this page matches \\""+s.find+"\\""); return; }
					if(null===s.type){
						/* Written down before the click, because a click that
						   submits a form is the last thing this document does. */
						state.done=i+1; state.click=i+1; keep();
						node.click();
						continue;
					}
					if(!("value" in node)){ stopped(i,"\\""+s.find+"\\" is not a field, so there is nowhere to type \\""+s.type+"\\""); return; }
					if(node.focus){ node.focus(); }
					node.value=s.type;
					node.dispatchEvent(new Event("input",{bubbles:true}));
					node.dispatchEvent(new Event("change",{bubbles:true}));
					/* A menu refuses a value it has no entry for and reads back
					   empty, which is how a shot list naming a shipping class the
					   shop has not got would otherwise photograph a form with one
					   field blank. */
					if(String(node.value)!==String(s.type)){
						stopped(i,"\\""+s.find+"\\" would not take \\""+s.type+"\\" and reads \\""+node.value+"\\"");
						return;
					}
					state.done=i+1; keep();
				}
			}
			if(steps.length){
				if(!store){
					report="this browser would not remember which steps had been taken, so a sequence cannot be followed";
				}else if(!prior){
					take();
				}else if(prior.why){
					report=prior.why;
				}else if(prior.done<steps.length){
					report="step "+prior.at+" of "+steps.length+" left the page before the rest of the sequence ran";
				}else if(prior.click!==steps.length){
					report="the page was left by step "+(prior.click||prior.at)+" of "+steps.length+", and only the last step may submit a form";
				}else if(!posted){
					report="the sequence finished and the page changed, but what came back was not the answer to a form: nothing was asked";
				}
			}
			if(!frame){return;}
			/* An animation that never ends has no right moment in it. A progress
			   bar with barber-pole stripes is somewhere different in its cycle
			   every render, so two runs of the same shot list came back with the
			   same set except for one band of one picture -- which is the kind of
			   difference that gets committed and then cannot be explained.
			   Stopping the animation drops each element back on the style it was
			   animating from, which for decoration is the picture anyway.

			   Only the endless ones, and unlike the transition rule this cannot
			   be done in CSS: an entrance animation runs once, often from
			   invisible, and turning that one off photographs nothing at all. */
			function settle(){
				var all=document.querySelectorAll("*");
				for(var i=0;i<all.length;i++){
					var s=getComputedStyle(all[i]);
					if(s&&s.animationIterationCount&&s.animationIterationCount.indexOf("infinite")>=0){
						all[i].style.animation="none";
					}
				}
			}
			settle();
			var w=window.pcShotWatch||{inflight:0,failed:[]};
			var touched=Date.now(), watching=null, drawn=null, verdict=null, steady=0, last=null;
			if(window.MutationObserver){
				watching=new MutationObserver(function(){ touched=Date.now(); });
				watching.observe(document.documentElement,
					{childList:true,subtree:true,attributes:true,characterData:true});
			}
			var giveUpAt=Date.now()+6000;
			function measure(){
				/* The union of every match, not the first: wp-admin lays its
				   columns out with floats, so the wrapper that looks like the
				   subject measures a few pixels high and a frame round it
				   photographs a strip of nothing. */
				var all=[].slice.call(document.querySelectorAll(frame)).map(function(n){
					return n.getBoundingClientRect();
				}).filter(function(b){ return b.width>1 && b.height>1; });
				if(!all.length){ return null; }
				return {
					left:Math.min.apply(null,all.map(function(b){return b.left;}))+window.scrollX,
					top:Math.min.apply(null,all.map(function(b){return b.top;}))+window.scrollY,
					right:Math.max.apply(null,all.map(function(b){return b.right;}))+window.scrollX,
					bottom:Math.max.apply(null,all.map(function(b){return b.bottom;}))+window.scrollY
				};
			}
			function put(a,b){
				return a&&b&&Math.abs(a.left-b.left)<1&&Math.abs(a.top-b.top)<1
					&&Math.abs(a.right-b.right)<1&&Math.abs(a.bottom-b.bottom)<1;
			}
			function unused(){
				return (w.excuse||[]).filter(function(e){ return !(w.used||{})[e]; });
			}
			function whyNow(){
				if(report){ return "undone"; }
				if(w.failed.length){ return "failed"; }
				if(w.inflight>0){ return "pending"; }
				return unused().length?"stale":"ok";
			}
			function why(){
				return steady>=2?whyNow():"moved";
			}
			function say(v){
				var lines=w.failed.slice(0);
				if("undone"===v){ lines.push(report); }
				if("pending"===v){ lines.push(w.inflight+" request(s) had not answered when the picture was taken"); }
				if("moved"===v){ lines.push("the subject was still moving when the picture was taken"); }
				if("stale"===v){ lines.push("nothing on this page asked for: "+unused().join(", ")); }
				var note=document.getElementById("pc-shot-why");
				if(!note){
					note=document.createElement("div");
					note.id="pc-shot-why";
					note.style.cssText="position:fixed;z-index:2147483647;left:0;top:0;max-width:100%%;"
						+"background:#111;color:#fff;font:12px/1.5 monospace;padding:6px 10px;white-space:pre-wrap;";
					document.body.appendChild(note);
				}
				note.textContent=v+"\\n"+lines.join("\\n");
			}
			function draw(box,v){
				/* The rule is drawn inside the frame rather than round it, and
				   the frame is clamped to the page. A subject flush against the
				   top of the document has no room for a rule above it, and an
				   outside rule there is simply not photographed -- which the
				   cropper cannot tell from a frame that was never drawn. */
				var L=Math.max(0,box.left-pad), T=Math.max(0,box.top-pad);
				var d=document.getElementById("pc-shot-frame");
				if(!d){
					d=document.createElement("div");
					d.id="pc-shot-frame";
					document.body.appendChild(d);
				}
				d.style.cssText="position:absolute;z-index:2147483646;pointer-events:none;"
					+"box-sizing:border-box;background:transparent;"
					+"box-shadow:inset 0 0 0 2px "+rule[v]+";"
					+"left:"+L+"px;top:"+T+"px;"
					+"width:"+(box.right+pad-L)+"px;"
					+"height:"+(box.bottom+pad-T)+"px;";
				if("ok"===v){
					/* A verdict can improve: a subject re-measured after it
					   moved may have nothing wrong with it by then, and the
					   reasons printed for the last one are not about this one. */
					var old=document.getElementById("pc-shot-why");
					if(old){ old.parentNode.removeChild(old); }
					return;
				}
				say(v);
			}
			setInterval(function(){
				var now=Date.now(), here=measure();
				/* A sequence that did not finish is not something waiting will
				   mend, and the screen is the wrong screen however settled it
				   looks. The rule goes on whatever can be measured, and on a
				   rectangle of its own if the subject is not there to measure --
				   a missing rule reads as a wrong selector, and the selector may
				   be the one thing here that is right. */
				if(report){
					if(drawn){ return; }
					drawn=here||{left:8,top:240,right:Math.min(608,(window.innerWidth||800)-8),bottom:400};
					verdict="undone";
					if(watching){ watching.disconnect(); watching=null; }
					draw(drawn,verdict);
					return;
				}
				if(!drawn){
					steady=put(here,last)?steady+1:0;
					last=here;
					var ready=here&&steady>=2&&w.inflight===0&&(now-touched)>=250;
					if(!ready&&now<giveUpAt){ return; }
					/* Nothing is drawn when the selector matched nothing: a
					   missing rule is the cropper telling you about the
					   selector, and a rule round nowhere would not be. */
					if(!here){ return; }
					verdict=why();
					drawn=here;
					/* Disconnected before the rule goes in, or drawing it looks
					   like one more mutation to wait for. */
					if(watching){ watching.disconnect(); watching=null; }
					/* Again, because the page has had a second to start
					   something the first pass could not have seen. */
					settle();
					draw(drawn,verdict);
					return;
				}
				if(w.failed.length){
					if("failed"!==verdict){ verdict="failed"; draw(drawn,verdict); }
					return;
				}
				if(put(here,drawn)){ return; }
				/* The subject moved after it was measured, and while there is
				   patience left the answer is to measure it again rather than to
				   refuse: the classic editor sets its own height a good half
				   second after the page has gone quiet and every request it made
				   has answered, which moves the panel below it twenty pixels up
				   the page. Nothing failed and nothing is still loading, so
				   refusing that would make an ordinary product screen
				   unphotographable. Only a subject still moving when the
				   patience runs out is refused. */
				if(here&&now<giveUpAt){
					drawn=here;
					verdict=whyNow();
					draw(drawn,verdict);
					return;
				}
				if("moved"!==verdict){ verdict="moved"; draw(drawn,verdict); }
			},150);
		});</script>',
		wp_json_encode( pc_shot_steps( $click ) ),
		wp_json_encode( $frame ),
		$pad,
		wp_json_encode( PC_SHOT_RULE ),
		$posted ? 'true' : 'false',
		wp_json_encode( $click )
	);
}
