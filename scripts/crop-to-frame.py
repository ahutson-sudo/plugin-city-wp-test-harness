#!/usr/bin/env python3
"""Crop a 2x render to the rule the page drew round its own subject.

    crop-to-frame.py <raw.png> <out.png> [margin]

The page marks its subject with an inset magenta rule (see
tests/helpers/screenshot-mode.php). Cropping to that rule rather than to
numbers read off a preview is what makes a set repeatable: a screen that grows
a field still comes out framed correctly, and nobody has to re-measure.
"""
import sys

from PIL import Image

SCALE = 2
RULE = 2 * SCALE  # the rule's own width, in device pixels


def frame_box(im):
    px = im.load()
    xs, ys = [], []
    for y in range(im.height):
        for x in range(im.width):
            r, g, b = px[x, y][:3]
            if r > 220 and g < 70 and b > 220:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def page_colour(im, box):
    """The colour just outside the frame, so an added margin matches the screen."""
    left, top, right, _ = box
    px = im.load()
    y = max(0, top - 6)
    samples = [px[x, y][:3] for x in range(left, min(right, im.width), 9)]
    return max(set(samples), key=samples.count) if samples else (240, 240, 241)


def main() -> int:
    raw, out = sys.argv[1], sys.argv[2]
    margin = int(sys.argv[3]) if len(sys.argv) > 3 else 0

    im = Image.open(raw).convert("RGB")
    box = frame_box(im)

    if box is None:
        # Almost always a selector that matched nothing, or a subject taller
        # than the viewport so that no complete rule was ever on screen.
        print(f"no frame found in {raw}: check the selector and the height", file=sys.stderr)
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
