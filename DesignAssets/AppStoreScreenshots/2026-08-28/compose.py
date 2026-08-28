#!/usr/bin/env python3
"""Compose localized App Store marketing screenshots from real app captures."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
WIDTH, HEIGHT = 1320, 2868
SCREEN_X, SCREEN_Y, SCREEN_WIDTH = 94, 410, 1132
SCREEN_HEIGHT = round(2868 * SCREEN_WIDTH / 1320)
FONT = "/System/Library/Fonts/HelveticaNeue.ttc"
FONT_BOLD_INDEX = 1

HEADLINES = {
    "uk": [
        "Усе важливе — в одному місці",
        "Знаходьте події поруч",
        "Усі деталі перед участю",
        "Відкривайте організації",
        "Контакти та можливості поруч",
        "Ваш простір у спільноті",
    ],
    "de": [
        "Alles Wichtige an einem Ort",
        "Events in deiner Nähe",
        "Alle Details auf einen Blick",
        "Organisationen entdecken",
        "Kontakte und Angebote",
        "Dein Bereich in der Community",
    ],
}


def gradient_background(width: int = WIDTH, height: int = HEIGHT) -> Image.Image:
    strip = Image.new("RGB", (1, height))
    pixels = strip.load()
    top = (7, 35, 82)
    middle = (22, 84, 174)
    bottom = (232, 242, 255)
    transition = min(760, height)
    for y in range(height):
        if y < transition:
            t = y / transition
            start, end = top, middle
        else:
            t = (y - transition) / max(1, height - transition)
            start, end = middle, bottom
        color = tuple(round(start[i] + (end[i] - start[i]) * t) for i in range(3))
        pixels[0, y] = color

    image = strip.resize((width, height))

    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    scale = width / WIDTH
    draw.ellipse(tuple(round(v * scale) for v in (1020, -210, 1510, 280)), fill=(255, 216, 0, 205))
    draw.ellipse(tuple(round(v * scale) for v in (-240, 160, 360, 760)), fill=(42, 125, 255, 95))
    draw.ellipse(tuple(round(v * scale) for v in (930, 500, 1450, 1020)), fill=(255, 255, 255, 25))
    return Image.alpha_composite(image.convert("RGBA"), overlay)


def fitted_font(text: str, max_width: int, max_size: int = 82, min_size: int = 56) -> ImageFont.FreeTypeFont:
    for size in range(max_size, min_size - 1, -2):
        font = ImageFont.truetype(FONT, size, index=FONT_BOLD_INDEX)
        bbox = font.getbbox(text)
        if bbox[2] - bbox[0] <= max_width:
            return font
    return ImageFont.truetype(FONT, min_size, index=FONT_BOLD_INDEX)


def compose(language: str, index: int, source: Path, destination: Path) -> None:
    canvas = gradient_background()
    draw = ImageDraw.Draw(canvas)

    badge_font = ImageFont.truetype(FONT, 42, index=FONT_BOLD_INDEX)
    draw.rounded_rectangle((94, 50, 270, 118), radius=34, fill=(255, 255, 255, 35), outline=(255, 255, 255, 80), width=2)
    draw.ellipse((114, 72, 134, 92), fill=(25, 112, 255, 255))
    draw.ellipse((142, 72, 162, 92), fill=(255, 216, 0, 255))
    draw.text((178, 82), "UAC", font=badge_font, fill=(7, 35, 82, 255), anchor="lm")

    headline = HEADLINES[language][index - 1]
    headline_font = fitted_font(headline, 1120)
    draw.text((WIDTH // 2, 240), headline, font=headline_font, fill="white", anchor="mm", align="center")

    raw = Image.open(source).convert("RGB")
    raw = raw.resize((SCREEN_WIDTH, SCREEN_HEIGHT), Image.Resampling.LANCZOS)
    radius = 72
    mask = Image.new("L", raw.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, raw.width - 1, raw.height - 1), radius=radius, fill=255)

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_shape = Image.new("RGBA", raw.size, (0, 0, 0, 0))
    shadow_shape.paste((0, 0, 0, 150), (0, 0, raw.width, raw.height), mask)
    shadow_shape = shadow_shape.filter(ImageFilter.GaussianBlur(36))
    shadow.alpha_composite(shadow_shape, (SCREEN_X, SCREEN_Y + 22))
    canvas = Image.alpha_composite(canvas, shadow)

    white_frame = Image.new("RGBA", (raw.width + 16, raw.height + 16), (255, 255, 255, 0))
    ImageDraw.Draw(white_frame).rounded_rectangle(
        (0, 0, white_frame.width - 1, white_frame.height - 1),
        radius=radius + 8,
        fill=(255, 255, 255, 255),
    )
    canvas.alpha_composite(white_frame, (SCREEN_X - 8, SCREEN_Y - 8))
    canvas.paste(raw, (SCREEN_X, SCREEN_Y), mask)

    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(destination, format="PNG", optimize=True)


def compose_ipad(language: str, index: int, source: Path, destination: Path) -> None:
    width, height = 2064, 2752
    screen_x, screen_y, screen_width, screen_height = 132, 330, 1800, 2400
    canvas = gradient_background(width, height)
    draw = ImageDraw.Draw(canvas)

    badge_font = ImageFont.truetype(FONT, 48, index=FONT_BOLD_INDEX)
    draw.rounded_rectangle((132, 48, 342, 124), radius=38, fill=(255, 255, 255, 255))
    draw.ellipse((156, 73, 178, 95), fill=(25, 112, 255, 255))
    draw.ellipse((187, 73, 209, 95), fill=(255, 216, 0, 255))
    draw.text((228, 86), "UAC", font=badge_font, fill=(7, 35, 82, 255), anchor="lm")

    headline = HEADLINES[language][index - 1]
    headline_font = fitted_font(headline, 1720, max_size=108, min_size=72)
    draw.text((width // 2, 210), headline, font=headline_font, fill="white", anchor="mm", align="center")

    raw = Image.open(source).convert("RGB").resize((screen_width, screen_height), Image.Resampling.LANCZOS)
    radius = 68
    mask = Image.new("L", raw.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, raw.width - 1, raw.height - 1), radius=radius, fill=255)

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_shape = Image.new("RGBA", raw.size, (0, 0, 0, 0))
    shadow_shape.paste((0, 0, 0, 135), (0, 0, raw.width, raw.height), mask)
    shadow_shape = shadow_shape.filter(ImageFilter.GaussianBlur(34))
    shadow.alpha_composite(shadow_shape, (screen_x, screen_y + 18))
    canvas = Image.alpha_composite(canvas, shadow)

    frame = Image.new("RGBA", (raw.width + 16, raw.height + 16), (255, 255, 255, 0))
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, frame.width - 1, frame.height - 1), radius=radius + 8, fill="white")
    canvas.alpha_composite(frame, (screen_x - 8, screen_y - 8))
    canvas.paste(raw, (screen_x, screen_y), mask)
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(destination, format="PNG", optimize=True)


def main() -> None:
    suffixes = ["home", "events", "event-detail", "organizations", "organization-detail", "profile"]
    for language in HEADLINES:
        for index, suffix in enumerate(suffixes, start=1):
            source = ROOT / "raw" / language / f"{index:02d}-{suffix}.png"
            destination = ROOT / "final" / language / f"uac-{language}-{index:02d}-{suffix}.png"
            compose(language, index, source, destination)
            ipad_source = ROOT / "raw-ipad" / language / f"{index:02d}-{suffix}.png"
            if ipad_source.exists():
                ipad_destination = ROOT / "final-ipad" / language / f"uac-{language}-{index:02d}-{suffix}.png"
                compose_ipad(language, index, ipad_source, ipad_destination)


if __name__ == "__main__":
    main()
