#!/usr/bin/env python3
"""Crop a 2x render to the rule the page drew round its own subject.

    crop-to-frame.py <raw.png> <out.png> [margin]

The page marks its subject with an inset rule (see
tests/helpers/screenshot-mode.php). Cropping to that rule rather than to
numbers read off a preview is what makes a set repeatable: a screen that grows
a field still comes out framed correctly, and nobody has to re-measure.

The rule's colour is also the page's verdict on itself, because a render is one
way traffic and there is nowhere else to put it. Magenta means the page finished
drawing itself and the crop may be taken. The other five each stop the run:
nothing is saved, and the reason is named. Keep this table in step with
PC_SHOT_RULE in the shim.

A rule that is not closed on all four sides stops the run as well. Chrome
photographs the viewport, so a subject taller or wider than it leaves a rule
with an edge missing -- and the crop then comes out of whatever part of the rule
was on screen, at a plausible size, looking exactly like a screenshot of
something a little smaller.
"""
import sys

from PIL import Image, ImageChops

SCALE = 2
RULE = 2 * SCALE  # the rule's own width, in device pixels

# Each verdict is the colour its rule is drawn in, said as which channels are
# up and which are down: nothing in wp-admin, a block theme or WooCommerce
# draws any of the six, and testing them as extremes rather than as exact
# values allows for the antialiasing on a fractional edge.
VERDICTS = (
    ("ok", "high", "low", "high"),
    ("failed", "low", "high", "low"),
    ("pending", "low", "high", "high"),
    ("moved", "high", "high", "low"),
    ("stale", "high", "low", "low"),
    ("undone", "low", "low", "high"),
)

REFUSED = {
    "failed": (
        "the page refused this render. Either it did not finish drawing itself -- "
        "a request or an image it needed did not arrive -- or it would have been a "
        "picture of a warned-about shop with the warning left out of it. Which, and "
        "what the warning said, is written across the top of the raw render."
    ),
    "pending": (
        "the page was still loading its own content when the picture was taken, "
        "so the crop would be of a screen part way through arriving."
    ),
    "moved": (
        "the subject moved after it had been measured, so the rule is no longer "
        "round it and the crop would be in the wrong place."
    ),
    "stale": (
        "a line in the shot list named something this page has not got. Either an "
        "allow line excused a request the page never makes, so the check it switches "
        "off is switched off for nothing, or part of the frame matched nothing, so "
        "the crop would be narrower than the shot asked for. Which of the two, and "
        "which fragment, is written across the top of the raw render."
    ),
    "undone": (
        "one of the steps in this shot's click column did not happen, so this is "
        "not the screen the shot asked for. Which step, and what stopped it, is "
        "written across the top of the raw render."
    ),
}

# A rule is at least four pixels along each of four sides, so anything smaller
# than this is page content that happens to be one of the four colours.
LEAST_RULE = 200

# An edge is drawn or it is not. The slack is for the antialiasing on a rule
# whose box came out of getBoundingClientRect() on a fractional boundary.
EDGE_DRAWN = 0.85


def masks(im):
    """One black-and-white mask per reserved colour, with its box and its size."""
    channels = im.split()[:3]
    up = [ch.point(lambda v: 255 if v > 220 else 0) for ch in channels]
    down = [ch.point(lambda v: 255 if v < 70 else 0) for ch in channels]

    found = {}
    for name, *wanted in VERDICTS:
        mask = None
        for i, level in enumerate(wanted):
            this = up[i] if level == "high" else down[i]
            mask = this if mask is None else ImageChops.multiply(mask, this)
        box = mask.getbbox()
        if box is None:
            continue
        size = mask.histogram()[255]
        if size >= LEAST_RULE:
            found[name] = (mask, box, size)
    return found


def open_edges(mask, box):
    """Which sides of the rule were not photographed, if any."""
    left, top, right, bottom = box
    px = mask.load()
    band = RULE // 2  # the middle of the rule's own width

    def drawn(points):
        points = [p for p in points if 0 <= p[0] < mask.width and 0 <= p[1] < mask.height]
        if not points:
            return 0.0
        return sum(1 for x, y in points if px[x, y]) / len(points)

    sides = {
        "top": [(x, top + band) for x in range(left, right, 3)],
        "bottom": [(x, bottom - 1 - band) for x in range(left, right, 3)],
        "left": [(left + band, y) for y in range(top, bottom, 3)],
        "right": [(right - 1 - band, y) for y in range(top, bottom, 3)],
    }
    return [side for side, points in sides.items() if drawn(points) < EDGE_DRAWN]


def page_colour(im, box):
    """The colour just outside the frame, so an added margin matches the screen.

    Above the frame, and below it when there is no above. A subject against the
    top of the document has its frame clamped to y=0, and a sample taken six
    pixels higher than that lands on the rule: every picture that asked for a
    margin got a bright magenta one, on the one shot in a set where the frame
    happens to start at the top of the page.
    """
    left, top, right, bottom = box
    px = im.load()

    for y in (top - 6, bottom + 5):
        if not 0 <= y < im.height:
            continue
        samples = [px[x, y][:3] for x in range(left, min(right, im.width), 9)]
        if samples:
            return max(set(samples), key=samples.count)

    return (240, 240, 241)


def main() -> int:
    raw, out = sys.argv[1], sys.argv[2]
    margin = int(sys.argv[3]) if len(sys.argv) > 3 else 0

    im = Image.open(raw).convert("RGB")
    found = masks(im)

    if not found:
        # A frame whose selectors matched nothing draws a red rule and says so,
        # so what is left is a rule that was drawn somewhere this render cannot
        # see it -- a subject below the fold -- or a page that never ran the
        # shim at all.
        print(
            f"no frame found in {raw}: nothing drew a rule. Either the subject is "
            "below the fold, so raise the height for this shot, or the page did not "
            "run the shim: look at the raw render and see which screen it is",
            file=sys.stderr,
        )
        return 1

    # The rule is whichever candidate closes on all four sides. Anything else of
    # one of these colours is page content, and page content is not a rectangle
    # drawn round the subject.
    closed = [name for name, *_ in VERDICTS if name in found and not open_edges(*found[name][:2])]
    name = closed[0] if closed else max(found, key=lambda n: found[n][2])
    mask, box, _ = found[name]

    if name != "ok":
        print(f"{raw} was refused: {REFUSED[name]}", file=sys.stderr)
        return 1

    missing = open_edges(mask, box)
    if missing:
        print(
            f"the rule in {raw} has no {' or '.join(missing)} edge, so the subject is "
            "bigger than the viewport it was rendered in: raise the width or the "
            "height for this shot.",
            file=sys.stderr,
        )
        return 1

    left, top, right, bottom = box
    cut = im.crop((left + RULE, top + RULE, right - RULE, bottom - RULE))
    final = cut.resize((cut.width // SCALE, cut.height // SCALE), Image.LANCZOS)

    if margin:
        bg = page_colour(im, box)
        padded = Image.new("RGB", (final.width + margin * 2, final.height + margin * 2), bg)
        padded.paste(final, (margin, margin))
        final = padded

    final.save(out, optimize=True)
    print(f"{out}  {final.width}x{final.height}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
