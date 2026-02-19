#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate Sparkle appcast XML")
    parser.add_argument("--output", required=True, help="Output appcast.xml path")
    parser.add_argument("--title", required=True, help="Application title")
    parser.add_argument("--link", required=True, help="Application website URL")
    parser.add_argument("--version", required=True, help="Short version string")
    parser.add_argument("--build", required=True, help="Build number")
    parser.add_argument("--download-url", required=True, help="DMG download URL")
    parser.add_argument("--ed-signature", required=True, help="Sparkle EdDSA signature")
    parser.add_argument("--length", required=True, help="DMG file size (bytes)")
    parser.add_argument("--minimum-system-version", default="14.1", help="Minimum macOS version")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")

    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>{args.title}</title>
    <link>{args.link}</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version {args.version}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{args.build}</sparkle:version>
      <sparkle:shortVersionString>{args.version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{args.minimum_system_version}</sparkle:minimumSystemVersion>
      <enclosure
        url="{args.download_url}"
        sparkle:edSignature="{args.ed_signature}"
        length="{args.length}"
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
"""

    Path(args.output).write_text(xml, encoding="utf-8")


if __name__ == "__main__":
    main()
