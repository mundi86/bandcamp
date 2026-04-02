#!/usr/bin/env python3
"""
Bandcamp Auto-Cart
Öffnet Bandcamp-URLs im Browser und klickt automatisch auf "Buy".

Install:
    pip install playwright
    playwright install chromium

Ausführen:
    python bandcamp-cart.py
"""

import time
import sys
import os
from pathlib import Path

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print("FEHLER: playwright ist nicht installiert!")
    print("")
    print("Installieren mit:")
    print("  pip install playwright")
    print("  playwright install chromium")
    print("")
    input("Enter zum Beenden...")
    sys.exit(1)


def load_urls(filepath: str) -> list[str]:
    """Liest URLs aus bandcamp.txt."""
    urls = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                urls.append(line)
    return urls


def add_to_cart(page, url: str, num: int, total: int) -> bool:
    """Öffnet eine Bandcamp-Seite und klickt auf Buy."""
    label = url.rstrip("/").split("/")[-1]
    print(f"[{num}/{total}] {label} ... ", end="", flush=True)

    try:
        page.goto(url, wait_until="domcontentloaded", timeout=30000)
        time.sleep(2)

        # Buy-Button finden und klicken
        buy_btn = page.locator("text=Buy Now").first
        if buy_btn.count() == 0:
            buy_btn = page.locator("text=Buy").first
        if buy_btn.count() == 0:
            buy_btn = page.locator(".buyItem").first

        if buy_btn.count() == 0:
            print("FEHLER (kein Buy-Button gefunden)")
            return False

        buy_btn.click()
        time.sleep(1)

        # Dialog: "name your price" → auf 0 setzen und bestätigen
        price_input = page.locator('input[type="text"]').first
        if price_input.count() > 0:
            try:
                price_input.fill("0")
                time.sleep(0.5)
            except Exception:
                pass

        # "Add to Cart" oder "OK" im Dialog klicken
        add_btn = page.locator("text=Add to Cart").first
        if add_btn.count() == 0:
            add_btn = page.locator("text=check out now").first
        if add_btn.count() == 0:
            add_btn = page.locator(".cart_button").first
        if add_btn.count() > 0:
            try:
                add_btn.click()
                time.sleep(1)
            except Exception:
                pass

        print("OK ✓")
        return True

    except Exception as e:
        print(f"FEHLER ({e})")
        return False


def main():
    script_dir = Path(__file__).parent
    link_file = script_dir / "bandcamp.txt"

    if not link_file.exists():
        print(f"FEHLER: {link_file} nicht gefunden!")
        input("Enter zum Beenden...")
        sys.exit(1)

    urls = load_urls(str(link_file))

    if not urls:
        print("FEHLER: Keine URLs in bandcamp.txt gefunden!")
        input("Enter zum Beenden...")
        sys.exit(1)

    print("==========================================")
    print("  Bandcamp → Warenkorb (automatisch)")
    print("==========================================")
    print(f"Quelle: bandcamp.txt")
    print(f"Titel:  {len(urls)}")
    print("")

    success = 0
    fail = 0

    with sync_playwright() as p:
        # Browser im sichtbaren Modus starten (nicht headless)
        browser = p.chromium.launch(headless=False)
        context = browser.new_context()
        page = context.new_page()

        for i, url in enumerate(urls):
            ok = add_to_cart(page, url, i + 1, len(urls))
            if ok:
                success += 1
            else:
                fail += 1
            time.sleep(1)

        # Warenkorb öffnen
        if success > 0:
            print("")
            print("Öffne Warenkorb zum Bezahlen...")
            page.goto("https://bandcamp.com/cart", wait_until="domcontentloaded")
            time.sleep(2)

        print("")
        print("==========================================")
        print(f"  Ergebnis: {success} OK / {fail} Fehler")
        print("==========================================")
        print("")
        print("Browser offen lassen → Checkout klicken!")

        # Browser offen lassen bis Enter gedrückt wird
        input("Enter zum Beenden (Browser wird geschlossen)...")

        browser.close()


if __name__ == "__main__":
    main()
