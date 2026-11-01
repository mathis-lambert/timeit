import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).resolve().parents[2] / 'deploy/publish-appcast.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


def feed(*builds):
    items = ''.join(
        f'<item><sparkle:version>{build}</sparkle:version>'
        f'<sparkle:channel>{channel}</sparkle:channel>'
        f'<enclosure url="{publisher.DOWNLOAD}v0.1.0/Timeit-{build}.zip" '
        'length="123" sparkle:edSignature="signature" /></item>'
        for build, channel in builds
    )
    return ('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            f'<channel>{items}</channel></rss>').encode()


class AppcastTests(unittest.TestCase):
    def test_channel_promotion_uses_new_build(self):
        publisher.validate_update(feed((1, 'beta')), feed((1, 'beta'), (2, 'stable')))

    def test_preserves_every_channel(self):
        with self.assertRaises(ValueError):
            publisher.validate_update(feed((1, 'stable'), (2, 'nightly')), feed((3, 'beta')))

    def test_rejects_stale_or_replaced_releases(self):
        for new in (feed((2, 'beta'), (1, 'stable')), feed((2, 'stable'))):
            with self.assertRaises(ValueError):
                publisher.validate_update(feed((2, 'beta')), new)

    def test_rejects_duplicate_builds_and_unknown_channels(self):
        for new in (feed((1, 'beta'), (1, 'stable')), feed((1, 'preview'))):
            with self.assertRaises(ValueError):
                publisher.entries(new)

    def test_atomic_publication_preserves_bytes_and_retry(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / 'updates'
            directory.mkdir()
            original = feed((1, 'stable'))
            publisher.publish(directory, original)
            publisher.publish(directory, original)
            with self.assertRaises(ValueError):
                publisher.publish(directory, feed((1, 'beta')))
            self.assertEqual((directory / 'appcast.xml').read_bytes(), original)
            self.assertEqual(list(directory.iterdir()), [directory / 'appcast.xml'])


if __name__ == '__main__':
    unittest.main()
