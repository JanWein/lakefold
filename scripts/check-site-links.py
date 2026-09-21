"""Check local HTML links, fragments and images in a generated pkgdown site."""
from html.parser import HTMLParser
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit

SITE_PREFIX = "/dataraft/"


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.links = []
        self.feed(path.read_text(encoding="utf-8"))

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        if tag == "a" and "name" in attrs:
            self.ids.add(attrs["name"])
        if tag in ("a", "img"):
            value = attrs.get("href" if tag == "a" else "src")
            if value:
                self.links.append(value)


def check(root):
    root = root.resolve()
    pages = {path: Page(path) for path in root.rglob("*.html")}
    errors = []
    checked = 0
    for path, page in pages.items():
        for link in page.links:
            url = urlsplit(link)
            if url.netloc or url.scheme:
                if url.netloc != "dataraft-r.github.io" or not url.path.startswith(SITE_PREFIX):
                    continue
                target = root / unquote(url.path[len(SITE_PREFIX):])
            elif url.path.startswith(SITE_PREFIX):
                target = root / unquote(url.path[len(SITE_PREFIX):])
            elif url.path.startswith("/"):
                target = root / unquote(url.path.lstrip("/"))
            elif url.path:
                target = path.parent / unquote(url.path)
            else:
                target = path
            target = target.resolve()
            if target.is_dir():
                target = target / "index.html"
            checked += 1
            if not target.is_relative_to(root) or not target.is_file():
                errors.append(f"{path.relative_to(root)}: missing target {link}")
            elif url.fragment and target in pages and unquote(url.fragment) not in pages[target].ids:
                errors.append(f"{path.relative_to(root)}: missing fragment {link}")
    if not pages:
        errors.append("No generated HTML pages found")
    for error in sorted(set(errors)):
        print(error)
    print(f"Checked {len(pages)} pages and {checked} local links; {len(set(errors))} errors")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(check(Path(sys.argv[1] if len(sys.argv) > 1 else "site")))
