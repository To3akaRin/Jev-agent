"""检查项目文档的本地链接，不访问外部网络。"""

import re
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key == "href":
                self.links.append(value)


def main():
    root = Path(__file__).resolve().parents[1]
    problems = []
    for path in [*root.glob("*.md"), *root.glob("docs/**/*.md")]:
        source = path.read_text(encoding="utf-8")
        parsed = Links()
        parsed.feed(source)
        for link in parsed.links + re.findall(r"\]\(([^)]+)\)", source):
            if link.startswith(("https://", "http://", "mailto:", "#")):
                continue
            target = unquote(link.split("#", 1)[0])
            if target and not (path.parent / target).exists():
                problems.append(f"{path.relative_to(root)}: {link}")
    if problems:
        raise SystemExit("\n".join(problems))
    print("Documentation local links OK")


if __name__ == "__main__":
    main()
