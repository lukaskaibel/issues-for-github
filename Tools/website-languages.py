#!/usr/bin/env python3
"""Keeps the website's languages in step.

The English pages are Website/index.html, support/, privacy/ and terms/; each other language has the same pages under
Website/<language>/ (de/, ja/, …). The Impressum exists once, in German. This script writes the parts every page
shares, between <!-- languages --> and <!-- /languages -->: the links search engines use to find each language, the
picker in the footer and, on the English pages, the redirect that opens a first visit in the browser's language.

    Tools/website-languages.py sync        rewrites those parts on every page; run it after adding a page or language
    Tools/website-languages.py new LANG    copies the English pages to Website/LANG/ for translating, with the paths
                                           to images and styles one level further up
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = os.path.join(ROOT, "Website")
URL = "https://lukaskaibel.github.io/issues-for-github/"
PAGES = ["", "support/", "privacy/", "terms/"]
# Folder, the html lang attribute, the language's own name, and its word for "Language".
LANGUAGES = [
    ("", "en", "English", "Language"),
    ("de/", "de", "Deutsch", "Sprache"),
    ("es/", "es", "Español", "Idioma"),
    ("fr/", "fr", "Français", "Langue"),
    ("pt-br/", "pt-BR", "Português (Brasil)", "Idioma"),
    ("ru/", "ru", "Русский", "Язык"),
    ("ja/", "ja", "日本語", "言語"),
    ("ko/", "ko", "한국어", "언어"),
    ("zh-hans/", "zh-Hans", "简体中文", "语言"),
]
GLOBE = ('<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.25"/>'
         '<path d="M1.75 8h12.5M8 1.75c1.8 1.7 2.7 3.8 2.7 6.25S9.8 12.55 8 14.25C6.2 12.55 5.3 10.45 5.3 8S6.2 3.45 8 1.75Z"/></svg>')


def path(folder, page):
    return os.path.join(SITE, folder, page, "index.html")


def up(folder, page):
    """From a page back to the site's root: "" for the English home page, "../../" for /de/support/."""
    return "../" * (folder.count("/") + page.count("/"))


def head_block(folder, page):
    lines = ["<!-- languages -->"]
    for other, code, _, _ in LANGUAGES:
        if os.path.exists(path(other, page)):
            lines.append(f'<link rel="alternate" hreflang="{code}" href="{URL}{other}{page}">')
    lines.append(f'<link rel="alternate" hreflang="x-default" href="{URL}{page}">')
    if folder == "":
        sites = ", ".join(f'{code.split("-")[0].lower()}: "{other.rstrip("/")}"' for other, code, _, _ in LANGUAGES if other)
        lines += [
            "<script>",
            "  // A first visit opens the page in the browser's language if the site has it; a language picked below sticks.",
            "  (function () {",
            f"    var sites = {{ {sites} }};",
            '    try { if (localStorage.getItem("language")) return; } catch (error) { return; }',
            '    var wanted = navigator.languages || [navigator.language || ""];',
            "    for (var i = 0; i < wanted.length; i++) {",
            '      var tag = String(wanted[i]).toLowerCase(), code = tag.split("-")[0];',
            '      if (code === "en") return;',
            '      if (code === "zh" && /-(hant|tw|hk|mo)\\b/.test(tag)) continue;',
            f'      if (sites[code]) {{ location.replace("{up(folder, page)}" + sites[code] + "/{page}"); return; }}',
            "    }",
            "  })();",
            "</script>",
        ]
    lines.append("<!-- /languages -->")
    return "\n  ".join(lines)


def footer_block(folder, page):
    current = next(l for l in LANGUAGES if l[0] == folder)
    items = []
    for other, code, name, _ in LANGUAGES:
        if not os.path.exists(path(other, page)):
            continue
        mark = ' aria-current="true"' if other == folder else ""
        href = up(folder, page) + other + page or "./"
        items.append(f'<li><a href="{href}" hreflang="{code}" lang="{code}" data-language="{code}"{mark}>{name}</a></li>')
    return "\n      ".join([
        "<!-- languages -->",
        '<details class="language">',
        f'  <summary aria-label="{current[3]}: {current[2]}">{GLOBE}{current[2]}</summary>',
        "  <ul>",
        *("    " + item for item in items),
        "  </ul>",
        "</details>",
        "<script>",
        '  document.querySelectorAll("[data-language]").forEach(function (link) {',
        '    link.addEventListener("click", function () {',
        '      try { localStorage.setItem("language", link.dataset.language); } catch (error) {}',
        "    });",
        "  });",
        "</script>",
        "<!-- /languages -->",
    ])


BLOCK = re.compile(r"<!-- languages -->.*?<!-- /languages -->", re.S)


def sync():
    for folder, *_ in LANGUAGES:
        for page in PAGES:
            file = path(folder, page)
            if not os.path.exists(file):
                continue
            with open(file, encoding="utf-8") as f:
                html = f.read()
            head, footer = head_block(folder, page), footer_block(folder, page)
            start = html.index("</head>")
            before, after = html[:start], html[start:]
            if BLOCK.search(before):
                before = BLOCK.sub(lambda _: head, before, count=1)
            else:
                before = before.rstrip() + "\n  " + head + "\n"
            if BLOCK.search(after):
                after = BLOCK.sub(lambda _: footer, after, count=1)
            else:
                nav = re.search(r"(\n    )<nav aria-label=[^>]*>.*?</nav>", after, re.S)
                indented = nav.group(0).replace("\n", "\n  ")
                after = after.replace(
                    nav.group(0), f'{nav.group(1)}<div class="footer-end">{indented}\n      {footer}\n    </div>', 1)
            with open(file, "w", encoding="utf-8") as f:
                f.write(before + after)
            print("synced", os.path.relpath(file, ROOT))


def new(code):
    folder = next(l[0] for l in LANGUAGES if l[1].lower() == code.lower() or l[0] == code.lower() + "/")
    for page in PAGES:
        with open(path("", page), encoding="utf-8") as f:
            html = f.read()
        html = BLOCK.sub("<!-- languages --><!-- /languages -->", html)
        html = html.replace('<html lang="en">', f'<html lang="{next(l[1] for l in LANGUAGES if l[0] == folder)}">', 1)

        # Pages of the site stay in this language's folder; everything else (images, styles, the Impressum) is
        # one level further from the root.
        def relink(match):
            attribute, url = match.group(1), match.group(2)
            if re.match(r"^(https?:|mailto:|#|/|data:)", url):
                return match.group(0)
            target = os.path.normpath(os.path.join("/" + page, url)).lstrip("/")
            target = target + "/" if url.endswith("/") and target else target
            if target in ("", ".") or target in PAGES:
                return match.group(0)
            return f'{attribute}="../{url}"'
        html = re.sub(r'\b(href|src|srcset)="([^"]*)"', relink, html)
        html = html.replace(f'property="og:url" content="{URL}{page}"', f'property="og:url" content="{URL}{folder}{page}"')
        target = path(folder, page)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w", encoding="utf-8") as f:
            f.write(html)
        print("created", os.path.relpath(target, ROOT))
    sync()


if __name__ == "__main__":
    if sys.argv[1:2] == ["sync"]:
        sync()
    elif sys.argv[1:2] == ["new"] and len(sys.argv) == 3:
        new(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(1)
