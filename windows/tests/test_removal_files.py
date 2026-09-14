"""Exercise the embedded cleanup helper on disposable files; never launch BTRemote."""
import argparse
import base64
import json
import pathlib
import subprocess
import tempfile
import unittest
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--powershell', default='pwsh')
args, remaining = parser.parse_known_args()
source = (pathlib.Path(__file__).resolve().parents[1] / 'BTRemote.Companion' / 'FinishRemoval.ps1').read_text()


class RemovalFilesTests(unittest.TestCase):
    def run_helper(self, paths):
        encoded = base64.b64encode(json.dumps([str(path) for path in paths]).encode()).decode()
        script = ("$showResult = $false\n$removingProcess = 2147483647\n"
                  + f"$encodedPaths = '{encoded}'\n"
                  + source.replace('Global\\BTRemoteCompanionInstall', 'BTRemoteRemovalTest' + uuid.uuid4().hex))
        command = base64.b64encode(script.encode('utf-16le')).decode()
        return subprocess.run([args.powershell, '-NoProfile', '-NonInteractive', '-EncodedCommand', command],
                              capture_output=True, text=True, timeout=30)

    def fixture(self, root):
        paths = [root / name for name in ['cache', 'data', 'install']]
        for path in paths:
            path.mkdir()
            (path / 'fixture.txt').write_text('disposable data')
        (paths[-1] / 'removal-pending').write_text('retry')
        return paths

    def test_removes_all_owned_files(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = self.fixture(pathlib.Path(directory).resolve())
            result = self.run_helper(paths)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(all(not path.exists() for path in paths))
            # Retrying after completed removal is harmless.
            self.assertEqual(self.run_helper(paths).returncode, 0)

    def test_linked_root_fails_without_deleting_target_or_retry_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory).resolve()
            paths = self.fixture(root)
            link = root / 'linked-cache'
            try:
                link.symlink_to(paths[0], target_is_directory=True)
            except OSError as error:
                self.skipTest(str(error))
            result = self.run_helper([link, *paths[1:]])
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('directory link', result.stderr)
            self.assertTrue((paths[0] / 'fixture.txt').exists())
            self.assertTrue((paths[-1] / 'removal-pending').exists())

    def test_link_inside_owned_tree_does_not_delete_its_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory).resolve()
            paths = self.fixture(root)
            unrelated = root / 'unrelated'
            unrelated.mkdir()
            (unrelated / 'keep.txt').write_text('keep')
            try:
                (paths[-1] / 'link').symlink_to(unrelated, target_is_directory=True)
            except OSError as error:
                self.skipTest(str(error))
            result = self.run_helper(paths)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((unrelated / 'keep.txt').read_text(), 'keep')


if __name__ == '__main__':
    unittest.main(argv=['test_removal_files.py', *remaining])
