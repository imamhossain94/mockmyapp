import os
import json
import base64
import re
from PIL import Image, ImageOps

DEVICES = [
    # Apple iPhone 14 Series
    {"brand": "apple", "model": "iphone-14", "name": "iPhone 14", "colors": [
        {"id": "blue", "name": "Blue", "hex": "#A0B4C7", "source_png": "iphone 14/notch/Blue.png"},
        {"id": "midnight", "name": "Midnight", "hex": "#1A1A1C", "source_png": "iphone 14/notch/Midnight.png"},
        {"id": "purple", "name": "Purple", "hex": "#E5D9EB", "source_png": "iphone 14/notch/Purple.png"},
        {"id": "red", "name": "Red", "hex": "#E31027", "source_png": "iphone 14/notch/Red.png"},
        {"id": "starlight", "name": "Starlight", "hex": "#FAF6F2", "source_png": "iphone 14/notch/Starlight.png"}
    ]},
    {"brand": "apple", "model": "iphone-14-pro", "name": "iPhone 14 Pro", "colors": [
        {"id": "deep-purple", "name": "Deep Purple", "hex": "#594F63", "source_png": "iphone 14/pill/Deep Purple.png"},
        {"id": "gold", "name": "Gold", "hex": "#F4E8CE", "source_png": "iphone 14/pill/Gold.png"},
        {"id": "silver", "name": "Silver", "hex": "#F0F2F2", "source_png": "iphone 14/pill/Silver.png"},
        {"id": "space-black", "name": "Space Black", "hex": "#403E3D", "source_png": "iphone 14/pill/Space Black.png"}
    ]},
    
    # Apple iPhone 15 Series (mapped to iPhone 14 notch/pill colors)
    {"brand": "apple", "model": "iphone-15", "name": "iPhone 15", "colors": [
        {"id": "black", "name": "Black", "hex": "#353638", "source_png": "iphone 14/notch/Midnight.png"},
        {"id": "blue", "name": "Blue", "hex": "#CEE0E4", "source_png": "iphone 14/notch/Blue.png"},
        {"id": "green", "name": "Green", "hex": "#D1E2D6", "source_png": "iphone 14/notch/Starlight.png"},
        {"id": "pink", "name": "Pink", "hex": "#FAD6D9", "source_png": "iphone 14/notch/Red.png"},
        {"id": "yellow", "name": "Yellow", "hex": "#FCE9C8", "source_png": "iphone 14/notch/Starlight.png"}
    ]},
    {"brand": "apple", "model": "iphone-15-pro", "name": "iPhone 15 Pro", "colors": [
        {"id": "black-titanium", "name": "Black Titanium", "hex": "#4B4B4B", "source_png": "iphone 14/pill/Space Black.png"},
        {"id": "blue-titanium", "name": "Blue Titanium", "hex": "#3A4555", "source_png": "iphone 14/pill/Deep Purple.png"},
        {"id": "natural-titanium", "name": "Natural Titanium", "hex": "#B1AFA7", "source_png": "iphone 14/pill/Gold.png"},
        {"id": "white-titanium", "name": "White Titanium", "hex": "#F2F1ED", "source_png": "iphone 14/pill/Silver.png"}
    ]},

    # Apple iPhone 16 Series
    {"brand": "apple", "model": "iphone-16", "name": "iPhone 16", "colors": [
        {"id": "black", "name": "Black", "hex": "#1A1A1C", "source_png": "iphone 14/notch/Midnight.png"},
        {"id": "pink", "name": "Pink", "hex": "#FAD6D9", "source_png": "iphone 14/notch/Red.png"},
        {"id": "teal", "name": "Teal", "hex": "#92B1AD", "source_png": "iphone 14/notch/Blue.png"},
        {"id": "ultramarine", "name": "Ultramarine", "hex": "#3A4D94", "source_png": "iphone 14/notch/Blue.png"},
        {"id": "white", "name": "White", "hex": "#FAF6F2", "source_png": "iphone 14/notch/Starlight.png"}
    ]},
    {"brand": "apple", "model": "iphone-16-pro", "name": "iPhone 16 Pro", "colors": [
        {"id": "black-titanium", "name": "Black Titanium", "hex": "#4B4B4B", "source_png": "iphone 14/pill/Space Black.png"},
        {"id": "desert-titanium", "name": "Desert Titanium", "hex": "#B59E87", "source_png": "iphone 14/pill/Gold.png"},
        {"id": "natural-titanium", "name": "Natural Titanium", "hex": "#B1AFA7", "source_png": "iphone 14/pill/Gold.png"},
        {"id": "white-titanium", "name": "White Titanium", "hex": "#F2F1ED", "source_png": "iphone 14/pill/Silver.png"}
    ]},

    # Apple iPhone 17 Series
    {"brand": "apple", "model": "iphone-17", "name": "iPhone 17", "colors": [
        {"id": "black", "name": "Black", "hex": "#1A1A1C", "source_png": "iphone 14/notch/Midnight.png"},
        {"id": "lavender", "name": "Lavender", "hex": "#D1C2DF", "source_png": "iphone 14/notch/Purple.png"},
        {"id": "mist-blue", "name": "Mist Blue", "hex": "#B3CDE0", "source_png": "iphone 14/notch/Blue.png"},
        {"id": "sage", "name": "Sage", "hex": "#9EAB94", "source_png": "iphone 14/notch/Starlight.png"},
        {"id": "white", "name": "White", "hex": "#FAF6F2", "source_png": "iphone 14/notch/Starlight.png"}
    ]},
    {"brand": "apple", "model": "iphone-17-pro", "name": "iPhone 17 Pro", "colors": [
        {"id": "cosmic-orange", "name": "Cosmic Orange", "hex": "#FF7F50", "source_png": "iphone 14/pill/Gold.png"},
        {"id": "deep-blue", "name": "Deep Blue", "hex": "#00008B", "source_png": "iphone 14/pill/Deep Purple.png"},
        {"id": "silver", "name": "Silver", "hex": "#F0F2F2", "source_png": "iphone 14/pill/Silver.png"}
    ]},

    # Apple iPad Pro 13"
    {"brand": "apple", "model": "ipad-pro-13", "name": "iPad Pro 13\"", "colors": [
        {"id": "silver", "name": "Silver", "hex": "#F0F2F2", "source_type": "generic_ai", "tint": "#E5E5E5"},
        {"id": "space-black", "name": "Space Black", "hex": "#403E3D", "source_type": "generic_ai", "tint": "#333333"}
    ]},

    # Samsung Devices
    {"brand": "samsung", "model": "galaxy-s24u", "name": "Galaxy S24 Ultra", "colors": [
        {"id": "titanium-gray", "name": "Titanium Gray", "hex": "#A2A2A0", "source_type": "samsung_s24u", "tint": None},
        {"id": "titanium-black", "name": "Titanium Black", "hex": "#4B4B4B", "source_type": "samsung_s24u", "tint": "#4B4B4B"},
        {"id": "titanium-violet", "name": "Titanium Violet", "hex": "#766A8A", "source_type": "samsung_s24u", "tint": "#766A8A"},
        {"id": "titanium-yellow", "name": "Titanium Yellow", "hex": "#E3C887", "source_type": "samsung_s24u", "tint": "#E3C887"}
    ]},
    {"brand": "samsung", "model": "galaxy-s26", "name": "Galaxy S26", "colors": [
        {"id": "titanium-black", "name": "Titanium Black", "hex": "#303030", "source_type": "samsung_s26", "tint": None},
        {"id": "titanium-silver", "name": "Titanium Silver", "hex": "#E0E0E0", "source_type": "samsung_s26", "tint": "#E0E0E0"}
    ]},

    # Google Devices
    {"brand": "google", "model": "pixel-8-pro", "name": "Pixel 8 Pro", "colors": [
        {"id": "obsidian", "name": "Obsidian", "hex": "#2B2B2B", "source_type": "generic_ai", "tint": "#2B2B2B"},
        {"id": "porcelain", "name": "Porcelain", "hex": "#F5F5F0", "source_type": "generic_ai", "tint": "#F5F5F0"},
        {"id": "bay", "name": "Bay", "hex": "#7CA7D8", "source_type": "generic_ai", "tint": "#7CA7D8"}
    ]},
    {"brand": "google", "model": "pixel-8", "name": "Pixel 8", "colors": [
        {"id": "obsidian", "name": "Obsidian", "hex": "#2B2B2B", "source_type": "generic_ai", "tint": "#2B2B2B"},
        {"id": "hazel", "name": "Hazel", "hex": "#767A75", "source_type": "generic_ai", "tint": "#767A75"},
        {"id": "rose", "name": "Rose", "hex": "#E8B2B4", "source_type": "generic_ai", "tint": "#E8B2B4"}
    ]},

    # OnePlus Devices
    {"brand": "oneplus", "model": "oneplus-14", "name": "OnePlus 14", "colors": [
        {"id": "obsidian-black", "name": "Obsidian Black", "hex": "#1A1A1A", "source_type": "generic_ai", "tint": "#1A1A1A"},
        {"id": "emerald-green", "name": "Emerald Green", "hex": "#2E5C53", "source_type": "generic_ai", "tint": "#2E5C53"},
        {"id": "glacier-white", "name": "Glacier White", "hex": "#F5F7FA", "source_type": "generic_ai", "tint": "#F5F7FA"}
    ]},

    # Nothing Devices
    {"brand": "nothing", "model": "phone-2a", "name": "Phone (2a)", "colors": [
        {"id": "black", "name": "Black", "hex": "#111111", "source_type": "generic_ai", "tint": "#111111"},
        {"id": "white", "name": "White", "hex": "#EEEEEE", "source_type": "generic_ai", "tint": "#EEEEEE"},
        {"id": "milk", "name": "Milk", "hex": "#EFEFEF", "source_type": "generic_ai", "tint": "#EFEFEF"}
    ]}
]


def extract_base64_from_svg(svg_path):
    with open(svg_path, 'r') as f:
        content = f.read()
    m = re.search(r'base64,([^\"]+)', content)
    if m:
        return base64.b64decode(m.group(1).strip().replace('\n', '').replace('\r', ''))
    return None

def find_screen_bounds(img):
    pixels = img.load()
    w, h = img.size
    cx, cy = w // 2, h // 2
    
    # scan for transparent screen
    x_min = cx
    while x_min > 0 and pixels[x_min, cy][3] < 10: x_min -= 1
    x_min += 1
    
    x_max = cx
    while x_max < w - 1 and pixels[x_max, cy][3] < 10: x_max += 1
    x_max -= 1
    scan_x = w // 4
    
    y_min = cy
    while y_min > 0 and pixels[scan_x, y_min][3] < 10: y_min -= 1
    y_min += 1
    
    y_max = cy
    while y_max < h - 1 and pixels[scan_x, y_max][3] < 10: y_max += 1
    y_max -= 1
    
    sw, sh = x_max - x_min + 1, y_max - y_min + 1
    return {
        "x": round(x_min / w, 4),
        "y": round(y_min / h, 4),
        "w": round(sw / w, 4),
        "h": round(sh / h, 4)
    }

def tint_image(img, hex_color):
    # Convert hex to RGB
    hex_color = hex_color.lstrip('#')
    rgb_color = tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))
    
    # Separate alpha channel
    r, g, b, a = img.split()
    gray = ImageOps.grayscale(img)
    # Colorize
    tinted = ImageOps.colorize(gray, black="black", white=rgb_color)
    
    # Re-apply alpha
    tinted = tinted.convert('RGBA')
    tinted.putalpha(a)
    return tinted

def process_ai_image(img_path):
    # Load AI generated image and remove white background & screen
    img = Image.open(img_path).convert('RGBA')
    pixels = img.load()
    w, h = img.size
    
    # Flood fill white pixels to transparent
    # Simplified approach: any pixel close to white becomes transparent
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if r > 240 and g > 240 and b > 240:
                pixels[x, y] = (255, 255, 255, 0)
    
    # Crop to content bounds
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
        
    # Resize to generic phone dimensions (e.g. 1000x2100)
    img = img.resize((1000, 2100), Image.Resampling.LANCZOS)
    return img

def main():
    import io
    manifest = []
    
    # Load Samsung SVGs as base images
    s24u_data = extract_base64_from_svg("assets/frames/samsung/samsung-galaxy-s24u__titanium-gray.svg")
    s26_data = extract_base64_from_svg("assets/frames/samsung/samsung-galaxy-s26__titanium-black.svg")
    
    s24u_img = Image.open(io.BytesIO(s24u_data)).convert("RGBA") if s24u_data else None
    s26_img = Image.open(io.BytesIO(s26_data)).convert("RGBA") if s26_data else None

    # Process AI generated image
    # A reference render kept outside the repository; without it the S26 base
    # stands in, as it always did on any machine but the one that made it.
    ai_img_path = "reference/pixel_8_frame.png"
    ai_img = process_ai_image(ai_img_path) if os.path.exists(ai_img_path) else s26_img

    for dev in DEVICES:
        brand = dev["brand"]
        model = dev["model"]
        brand_dir = f"assets/frames/{brand}"
        os.makedirs(brand_dir, exist_ok=True)
        
        variants = []
        bounds = None
        w, h = 0, 0
        
        for color in dev["colors"]:
            cid = color["id"]
            svg_filename = f"{brand}-{model}__{cid}.svg"
            svg_path = os.path.join(brand_dir, svg_filename)
            
            # Determine source image
            if "source_png" in color:
                src_path = f"reference/new_frames/{color['source_png']}"
                if not os.path.exists(src_path):
                    print(f"Missing {src_path}")
                    continue
                img = Image.open(src_path).convert("RGBA")
            elif "source_type" in color:
                stype = color["source_type"]
                if stype == "samsung_s24u":
                    img = s24u_img.copy() if s24u_img else None
                elif stype == "samsung_s26":
                    img = s26_img.copy() if s26_img else None
                elif stype == "generic_ai":
                    img = ai_img.copy() if ai_img else None
                
                if not img:
                    continue
                    
                if color.get("tint"):
                    img = tint_image(img, color["tint"])
            else:
                continue

            # Calculate screen bounds
            bounds = find_screen_bounds(img)
            
            # Convert to base64
            buffered = io.BytesIO()
            img.save(buffered, format="PNG")
            b64_str = base64.b64encode(buffered.getvalue()).decode("utf-8")
            
            # Write SVG
            w, h = img.size
            svg_content = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
  <image width="{w}" height="{h}" xlink:href="data:image/png;base64,{b64_str}"/>
</svg>'''
            
            with open(svg_path, "w") as f:
                f.write(svg_content)
                
            # Add to variant list
            variants.append({
                "id": cid,
                "name": color["name"],
                "asset": f"assets/frames/{brand}/{svg_filename}",
                "frameColor": color["hex"]
            })
            print(f"Generated {svg_path}")

        if not variants:
            continue
            
        # Add device to manifest
        platform = "ios" if brand == "apple" else "android"
        form_factor = "tablet" if "ipad" in model else "phone"
        manifest.append({
            "id": f"{brand}-{model}",
            "brand": brand.capitalize(),
            "model": dev["name"],
            "platform": platform,
            "releaseYear": 2024,
            "screenAspect": round(bounds["w"] * w / (bounds["h"] * h), 4),
            "frameAspect": round(w / h, 4),
            "screenRect": bounds,
            "cornerRadiusPct": 0.1,
            "cutout": "pill" if "pro" in model else "notch",
            "formFactor": form_factor,
            "variants": variants
        })

    # Write manifest.json
    final_manifest = {
        "schema": 2,
        "generatedBy": "tool/generate_realistic_frames.py",
        "devices": manifest
    }
    with open("assets/frames/manifest.json", "w") as f:
        json.dump(final_manifest, f, indent=2)
    print("Updated manifest.json")

if __name__ == "__main__":
    main()
