#!/usr/bin/env python3
"""Generate app icons from the favicon design (red circle with white arrow)."""

from PIL import Image, ImageDraw
import os

# Icon sizes needed for macOS app icon
ICON_SIZES = [
    (16, 1),    # icon_16x16.png
    (16, 2),    # icon_16x16@2x.png (32px)
    (32, 1),    # icon_32x32.png
    (32, 2),    # icon_32x32@2x.png (64px)
    (64, 1),    # icon_64x64.png
    (64, 2),    # icon_64x64@2x.png (128px)
    (128, 1),   # icon_128x128.png
    (128, 2),   # icon_128x128@2x.png (256px)
    (256, 1),   # icon_256x256.png
    (256, 2),   # icon_256x256@2x.png (512px)
    (512, 1),   # icon_512x512.png
    (512, 2),   # icon_512x512@2x.png (1024px)
]

# Menu bar icon sizes (template images - black with alpha)
MENUBAR_SIZES = [
    (18, 1),    # Standard menu bar size
    (18, 2),    # Retina
    (22, 1),    # Alternative size
    (22, 2),    # Retina
]

# Colors from favicon
RED = "#DC3545"
WHITE = "#FFFFFF"
BLACK = "#000000"


def hex_to_rgb(hex_color):
    """Convert hex color to RGB tuple."""
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))


def create_app_icon(size):
    """Create the app icon at specified size."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Scale factor based on original 100x100 viewBox
    scale = size / 100

    # Draw red circle (cx=50, cy=50, r=48)
    circle_center = 50 * scale
    circle_radius = 48 * scale
    draw.ellipse(
        [circle_center - circle_radius, circle_center - circle_radius,
         circle_center + circle_radius, circle_center + circle_radius],
        fill=hex_to_rgb(RED)
    )

    # Draw the arrow
    # Original path: M50 20 L50 55 (vertical line) M35 40 L50 55 L65 40 (arrow head)
    stroke_width = max(1, int(8 * scale))

    # Vertical line from (50,20) to (50,55)
    x = 50 * scale
    y1 = 20 * scale
    y2 = 55 * scale

    # Arrow head points
    left_x = 35 * scale
    right_x = 65 * scale
    arrow_y = 40 * scale
    tip_x = 50 * scale
    tip_y = 55 * scale

    # Draw with anti-aliasing by using lines with rounded caps
    # Vertical line
    draw.line([(x, y1), (x, y2)], fill=hex_to_rgb(WHITE), width=stroke_width)

    # Arrow head - left side
    draw.line([(left_x, arrow_y), (tip_x, tip_y)], fill=hex_to_rgb(WHITE), width=stroke_width)

    # Arrow head - right side
    draw.line([(right_x, arrow_y), (tip_x, tip_y)], fill=hex_to_rgb(WHITE), width=stroke_width)

    # Draw rounded caps at line endpoints
    cap_radius = stroke_width // 2
    for point in [(x, y1), (left_x, arrow_y), (right_x, arrow_y), (tip_x, tip_y)]:
        draw.ellipse(
            [point[0] - cap_radius, point[1] - cap_radius,
             point[0] + cap_radius, point[1] + cap_radius],
            fill=hex_to_rgb(WHITE)
        )

    return img


def create_menubar_icon(target_size, is_template=True):
    """Create menu bar icon (monochrome template) with proper anti-aliasing."""
    # Draw at 8x size for smooth anti-aliasing, then scale down
    render_size = 256
    img = Image.new('RGBA', (render_size, render_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # For template images, use black (will be inverted by system for dark mode)
    color = hex_to_rgb(BLACK) if is_template else hex_to_rgb(RED)

    # All coordinates based on 256px canvas
    center = 128

    # Draw filled circle
    circle_radius = 110
    draw.ellipse(
        [center - circle_radius, center - circle_radius,
         center + circle_radius, center + circle_radius],
        fill=color
    )

    # Cut out inner circle to create ring effect (using transparent)
    inner_radius = 85
    draw.ellipse(
        [center - inner_radius, center - inner_radius,
         center + inner_radius, center + inner_radius],
        fill=(0, 0, 0, 0)
    )

    # Draw the arrow (thicker lines)
    stroke_width = 28

    # Vertical line
    x = center
    y1 = 55
    y2 = 155
    draw.line([(x, y1), (x, y2)], fill=color, width=stroke_width)

    # Arrow head
    left_x = 75
    right_x = 181
    arrow_y = 110
    tip_y = 165
    draw.line([(left_x, arrow_y), (center, tip_y)], fill=color, width=stroke_width)
    draw.line([(right_x, arrow_y), (center, tip_y)], fill=color, width=stroke_width)

    # Rounded caps
    cap_radius = stroke_width // 2
    for point in [(x, y1), (left_x, arrow_y), (right_x, arrow_y), (center, tip_y)]:
        draw.ellipse(
            [point[0] - cap_radius, point[1] - cap_radius,
             point[0] + cap_radius, point[1] + cap_radius],
            fill=color
        )

    # Scale down to target size with high-quality resampling
    img = img.resize((target_size, target_size), Image.LANCZOS)

    return img


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    iconset_dir = os.path.join(script_dir, 'AppIcon.iconset')
    resources_dir = os.path.join(script_dir, 'NotToday', 'Sources', 'NotToday', 'Resources')

    # Create directories if they don't exist
    os.makedirs(iconset_dir, exist_ok=True)
    os.makedirs(resources_dir, exist_ok=True)

    print("Generating app icons...")

    # Generate app icons
    for base_size, scale in ICON_SIZES:
        actual_size = base_size * scale
        img = create_app_icon(actual_size)

        if scale == 1:
            filename = f'icon_{base_size}x{base_size}.png'
        else:
            filename = f'icon_{base_size}x{base_size}@{scale}x.png'

        filepath = os.path.join(iconset_dir, filename)
        img.save(filepath, 'PNG')
        print(f"  Created {filename} ({actual_size}x{actual_size})")

    print("\nGenerating menu bar icons...")

    # Generate menu bar icons
    for base_size, scale in MENUBAR_SIZES:
        actual_size = base_size * scale
        img = create_menubar_icon(actual_size)

        if scale == 1:
            filename = f'menubar_icon_{base_size}x{base_size}.png'
        else:
            filename = f'menubar_icon_{base_size}x{base_size}@{scale}x.png'

        filepath = os.path.join(resources_dir, filename)
        img.save(filepath, 'PNG')
        print(f"  Created {filename} ({actual_size}x{actual_size})")

    print("\nDone! Now run 'iconutil -c icns AppIcon.iconset' to create the .icns file")


if __name__ == '__main__':
    main()
