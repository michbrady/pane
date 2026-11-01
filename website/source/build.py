#!/usr/bin/env python3
"""Builds ../index.html from page.html: inlines the screenshots and fills in the download's size and checksum.

Usage: python3 website/source/build.py     (run from the repo root; website/website/Pane.dmg must exist)
"""
import base64, hashlib, os, re, subprocess, urllib.parse

here = os.path.dirname(os.path.abspath(__file__))
site = os.path.dirname(here)

logo = '''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Pane logo">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#22b3b8"/><stop offset="1" stop-color="#0c8087"/></linearGradient></defs>
<rect width="1024" height="1024" rx="230" fill="url(#g)"/>
<g transform="translate(512 512) scale(1.15) translate(-512 -512)">
<g fill="#fff" opacity=".6"><rect x="220" y="330" width="584" height="420" rx="64"/><rect x="220" y="270" width="236" height="120" rx="48"/></g>
<g fill="#fff"><rect x="284" y="406" width="150" height="276" rx="32"/><rect x="466" y="406" width="274" height="276" rx="32"/></g>
</g>
</svg>'''

def image(name):
    with open(os.path.join(here, "shots", name + ".png"), "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()

dmg_path = os.path.join(site, "Pane.dmg")
data = open(dmg_path, "rb").read()
size_mb = len(data) / 1_000_000

# The page says "notarized" only when Apple's ticket is really stapled to this file.
notarized = subprocess.run(["xcrun", "stapler", "validate", dmg_path], capture_output=True).returncode == 0
STEP3 = (
    '<li><h3>Open Pane</h3><p>Open Pane from Applications. It is signed and notarized by Apple, so it opens without a warning. '
    'The first time, macOS may ask you to confirm that it came from the internet: choose <b>Open</b>.</p></li>'
) if notarized else (
    '<li><h3>Open it once</h3><p>Open Pane from Applications. macOS will say it cannot check Pane for malware, because this early '
    'version is not notarized by Apple yet. Open <b>System Settings</b>, choose <b>Privacy &amp; Security</b>, scroll to Security, '
    'and choose <b>Open Anyway</b>. You only do this the first time.</p></li>'
)
# What people will see the first time, so it does not look like a warning. Only true once Apple has notarized the file.
FIRST_OPEN_NOTE = (
    '<div class="notice"><p><b>The first time you open Pane, macOS asks you to confirm.</b></p>'
    '<p>It says that Pane was downloaded from the internet and asks if you want to open it. It also tells you that Apple '
    'checked it for malicious software and found none. That is normal for any app you download. Choose <b>Open</b>. '
    'It only asks once.</p></div>'
) if notarized else ""
NOTARY_BULLET = (
    '<li><b>Signed and notarized.</b> Apple has checked this download for known malicious software.</li>'
) if notarized else (
    '<li><b>Not notarized.</b> That is why macOS asks you to allow it. A notarized download is planned.</li>'
)

page = open(os.path.join(here, "page.html")).read()
fills = {
    "FAVICON": urllib.parse.quote(logo.replace("\n", ""), safe=""),
    "LOGO": logo,
    "DL_SIZE": f"{size_mb:.1f} MB",
    "DL_SHA": hashlib.sha256(data).hexdigest(),
    "INSTALLER": image("installer"),
    "STEP3": STEP3,
    "FIRST_OPEN_NOTE": FIRST_OPEN_NOTE,
    "NOTARY_BULLET": NOTARY_BULLET,
    "WINDOW_LIGHT": image("window-light"), "WINDOW_DARK": image("window-dark"),
    "REMOTE_LIGHT": image("remote-light"), "REMOTE_DARK": image("remote-dark"),
    "PREVIEW_LIGHT": image("preview-image-light"), "PREVIEW_DARK": image("preview-image-dark"),
    "TABS_LIGHT": image("tabs-light"), "TABS_DARK": image("tabs-dark"),
}
for key, value in fills.items():
    page = page.replace("{{%s}}" % key, value)
assert "{{" not in page, "an unfilled placeholder is left"
out = os.environ.get("PAGE_OUT") or os.path.join(site, "index.html")
open(out, "w").write(page)
# The privacy page: the same styling and logo as the main page, so the two always match.
style = re.search(r"<style>(.*?)</style>", page, re.S).group(1)
privacy = open(os.path.join(here, "privacy.html")).read()
for key, value in {"STYLE": style, "LOGO": logo, "FAVICON": fills["FAVICON"]}.items():
    privacy = privacy.replace("{{%s}}" % key, value)
assert "{{" not in privacy, "an unfilled placeholder is left in the privacy page"
# The pages must point at each other, and the tip link must be there.
assert 'href="privacy.html"' in page, "the main page does not link to the privacy page"
assert 'href="./"' in privacy, "the privacy page does not link back"
assert "https://ko-fi.com/bradysbit" in page, "the Ko-fi tip link is missing"
privacy_out = os.environ.get("PRIVACY_OUT") or os.path.join(site, "privacy.html")
open(privacy_out, "w").write(privacy)
print(f"wrote {privacy_out}")
print(f"download is {'signed and NOTARIZED' if notarized else 'not notarized'}")
print(f"wrote {out} ({len(page) // 1024} KB); Pane.dmg is {fills['DL_SIZE']}, sha256 {fills['DL_SHA'][:16]}...")
