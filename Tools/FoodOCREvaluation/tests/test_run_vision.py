import hashlib
import tempfile
import unittest
from pathlib import Path

from run_vision import preflight


class VisionPreflightTests(unittest.TestCase):
    def test_checks_all_images_before_opening_the_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / "panel.jpg"
            image.write_bytes(b"public image fixture")
            digest = hashlib.sha256(image.read_bytes()).hexdigest()
            manifest = {"panels": [{
                "panel_id": "panel", "split": "tuning",
                "local_image": image.name, "image_sha256": digest,
            }]}
            self.assertEqual(len(preflight(manifest, root, root / "results", "tuning")), 1)
            image.write_bytes(b"changed bytes")
            with self.assertRaisesRegex(ValueError, "image hash mismatch"):
                preflight(manifest, root, root / "results", "tuning")

    def test_refuses_existing_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "marker").write_text("previous run")
            with self.assertRaisesRegex(ValueError, "not empty"):
                preflight({"panels": []}, root, root, None)


if __name__ == "__main__":
    unittest.main()
