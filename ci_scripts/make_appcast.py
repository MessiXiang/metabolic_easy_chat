#!/usr/bin/env python3
import argparse
import html
import hashlib
from email.utils import formatdate
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a minimal Sparkle appcast.xml")
    parser.add_argument("--output", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--short-version", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--asset-path", required=True)
    parser.add_argument("--signature", default="")
    parser.add_argument("--title", default="metabolic_easy_chat update")
    parser.add_argument("--description", default="Automated GitHub Actions build from main.")
    args = parser.parse_args()

    asset_path = Path(args.asset_path)
    data = asset_path.read_bytes()
    length = len(data)
    sha256 = hashlib.sha256(data).hexdigest()
    sparkle_signature = f' sparkle:edSignature="{html.escape(args.signature, quote=True)}"' if args.signature else ""

    pub_date = formatdate(usegmt=True)

    xml = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>metabolic_easy_chat Appcast</title>
    <description>Updates for metabolic_easy_chat</description>
    <language>zh-CN</language>
    <item>
      <title>{html.escape(args.title)}</title>
      <description><![CDATA[{html.escape(args.description)}<br/>SHA-256: {sha256}]]></description>
      <pubDate>{pub_date}</pubDate>
      <enclosure
        url="{html.escape(args.download_url, quote=True)}"
        sparkle:version="{html.escape(args.version, quote=True)}"
        sparkle:shortVersionString="{html.escape(args.short_version, quote=True)}"
        length="{length}"
        type="application/octet-stream"{sparkle_signature} />
    </item>
  </channel>
</rss>
'''
    Path(args.output).write_text(xml, encoding="utf-8")


if __name__ == "__main__":
    main()
