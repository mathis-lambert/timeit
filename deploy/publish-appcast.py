#!/usr/bin/env python3
"""Atomically install a feed verified by the trusted CI signer; never rewrite its bytes."""
import fcntl
import os
from pathlib import Path
import re
import sys
import tempfile
import xml.etree.ElementTree as ET

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
DOWNLOAD = 'https://github.com/mathis-lambert/timeit/releases/download/'


def entries(data):
    root = ET.fromstring(data)
    if root.tag != 'rss' or root.find('channel') is None:
        raise ValueError('Expected a Sparkle RSS channel')
    result = {}
    for item in root.findall('./channel/item'):
        version = item.findtext(SPARKLE + 'version')
        channel = item.findtext(SPARKLE + 'channel', 'stable')
        enclosure = item.find('enclosure')
        if not version or not re.fullmatch(r'[1-9][0-9]*', version):
            raise ValueError('Build numbers must be positive integers')
        if channel not in ('stable', 'beta', 'nightly') or enclosure is None:
            raise ValueError('Invalid channel or missing archive')
        url = enclosure.get('url', '')
        signature = enclosure.get(SPARKLE + 'edSignature', '')
        length = enclosure.get('length', '')
        if not url.startswith(DOWNLOAD) or not url.endswith('.zip'):
            raise ValueError('Only Timeit GitHub release ZIPs are allowed')
        if not signature or not length.isdecimal() or int(length) <= 0:
            raise ValueError('Archive signature and length are required')
        build = int(version)
        if build in result:
            raise ValueError('Duplicate build')
        result[build] = (channel, url, signature, length)
    if not result:
        raise ValueError('Empty feed')
    return result


def validate_update(previous, incoming):
    new = entries(incoming)
    if previous is None:
        return
    old = entries(previous)
    if any(new.get(build) != value for build, value in old.items()):
        raise ValueError('Existing releases must be preserved unchanged')
    additions = new.keys() - old.keys()
    if additions and min(additions) <= max(old):
        raise ValueError('New builds must increase globally across channels')


def publish(directory, data):
    directory = Path(directory)
    # The deployment provisions this directory; do not silently target another path.
    if not directory.is_dir():
        raise ValueError('Updates directory is missing')
    with (directory.parent / '.appcast.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        target = directory / 'appcast.xml'
        previous = target.read_bytes() if target.exists() else None
        validate_update(previous, data)
        if previous == data:
            return
        descriptor, temporary = tempfile.mkstemp(prefix='.appcast-', dir=directory)
        try:
            with os.fdopen(descriptor, 'wb') as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
                os.fchmod(stream.fileno(), 0o644)
            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


if __name__ == '__main__':
    payload = sys.stdin.buffer.read(8 * 1024 * 1024 + 1)
    if len(payload) > 8 * 1024 * 1024:
        raise SystemExit('Feed exceeds 8 MiB')
    publish(Path(sys.argv[1]), payload)
