#!/usr/bin/env python3
"""Lay a captured set out on one page, so it can be judged at a glance.

    contact-sheet.py <shots.tsv> <dir> [out.png] [--title "..."]

A set is wrong in ways no single picture shows: two shots at different scales,
one cropped tighter than the rest, a caption that turns out to describe the
screen next to it. All of those are obvious side by side and invisible one at a
time, which is why this exists and why it reads the same shot list the capture
did -- the order and the captions are the shot list's, not this script's.

It is a review aid rather than a deliverable. Nothing ships it.
"""
import argparse
import pathlib
import sys
import textwrap

from PIL import Image, ImageDraw, ImageFont

CELL_W = 620
COLUMNS = 2
GAP = 34
PAD = 44
CAPTION_LINES = 3

BG = (255, 255, 255)
INK = (22, 26, 33)
MUTED = (104, 112, 124)
LINE = (219, 223, 229)
ACCENT = (91, 45, 156)

# Liberation first because the sets in this range were drawn with it. A box
# without it gets DejaVu, and then the PIL default, and is told which -- the
# same substitution happening silently is how two sheets come to disagree about
# letterforms for no reason anybody can see.
FONT_DIRS = (
    ("/usr/share/fonts/truetype/liberation", "LiberationSans-Regular.ttf", "LiberationSans-Bold.ttf"),
    ("/usr/share/fonts/truetype/dejavu", "DejaVuSans.ttf", "DejaVuSans-Bold.ttf"),
)


def fonts():
    """Return (regular_path, bold_path), or (None, None) for PIL's own."""
    for directory, regular, bold in FONT_DIRS:
        base = pathlib.Path(directory)
        if (base / regular).is_file() and (base / bold).is_file():
            return str(base / regular), str(base / bold)

    print(
        "No Liberation or DejaVu fonts found; falling back to PIL's built-in "
        "face, so this sheet will not match one drawn elsewhere.",
        file=sys.stderr,
    )
    return None, None


def face(path, size):
    return ImageFont.truetype(path, size) if path else ImageFont.load_default()


def read_shot_list(path):
    """Names and captions, in the shot list's own order."""
    shots = []
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split("\t")
        name = fields[0].strip()
        caption = fields[8].strip() if len(fields) > 8 else ""
        shots.append((name, caption))
    return shots


def fit(im, width):
    if im.width <= width:
        return im
    return im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)


def build(shots, directory, out_path, title, subtitle):
    regular, bold = fonts()
    f_title = face(bold, 34)
    f_sub = face(regular, 19)
    f_num = face(bold, 20)
    f_cap = face(regular, 17)
    f_meta = face(regular, 15)

    cells = []
    for index, (name, caption) in enumerate(shots, start=1):
        image_path = directory / f"{name}.png"
        if not image_path.is_file():
            # The shot list is the record of what should exist, so a gap here
            # means the capture did not finish. Saying so beats drawing a sheet
            # with a hole in it that somebody has to notice.
            sys.exit(f"{image_path} is in the shot list but was not captured.")
        original = Image.open(image_path).convert("RGB")
        cells.append((str(index), caption or name, image_path.name, original.size, fit(original, CELL_W)))

    header_h = 150
    placed = []
    y = header_h
    for row_start in range(0, len(cells), COLUMNS):
        row = cells[row_start:row_start + COLUMNS]
        caption_space = 22 + CAPTION_LINES * 23
        for column, cell in enumerate(row):
            placed.append((PAD + column * (CELL_W + GAP), y, cell))
        y += max(c[4].height for c in row) + caption_space + GAP + 16

    sheet = Image.new("RGB", (PAD * 2 + CELL_W * COLUMNS + GAP, y + PAD), BG)
    draw = ImageDraw.Draw(sheet)

    draw.text((PAD, PAD), title, font=f_title, fill=INK)
    draw.text((PAD, PAD + 46), subtitle, font=f_sub, fill=MUTED)
    draw.line((PAD, header_h - 22, sheet.width - PAD, header_h - 22), fill=LINE, width=1)

    for x, top, (number, caption, filename, original_size, image) in placed:
        draw.text((x, top), number, font=f_num, fill=ACCENT)
        lines = textwrap.wrap(caption, 66)[:CAPTION_LINES]
        for n, line in enumerate(lines):
            draw.text((x + 52, top + n * 23), line, font=f_cap, fill=INK)

        image_top = top + max(2, len(lines)) * 23 + 14
        draw.rectangle((x - 1, image_top - 1, x + image.width, image_top + image.height), outline=LINE)
        sheet.paste(image, (x, image_top))
        draw.text(
            (x, image_top + image.height + 10),
            f"{filename} — {original_size[0]}x{original_size[1]}px",
            font=f_meta,
            fill=MUTED,
        )

    sheet.save(out_path, optimize=True)
    print(f"{out_path}  {sheet.width}x{sheet.height}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("shots", help="the shot list the capture used")
    parser.add_argument("directory", help="where the capture wrote its PNGs")
    parser.add_argument("out", nargs="?", help="output file; defaults to contact-sheet.png beside them")
    parser.add_argument("--title", default="Generated screenshots")
    parser.add_argument(
        "--subtitle",
        default="Captured from the plugin running on WordPress and WooCommerce. Shop data seeded, not hand-made.",
    )
    args = parser.parse_args()

    directory = pathlib.Path(args.directory)
    shots = read_shot_list(args.shots)
    if not shots:
        sys.exit(f"No shots in {args.shots}.")

    build(
        shots,
        directory,
        pathlib.Path(args.out) if args.out else directory / "contact-sheet.png",
        args.title,
        args.subtitle,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
