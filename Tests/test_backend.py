import importlib.util
import io
import os
from pathlib import Path
import plistlib
import subprocess
import tarfile
import tempfile
import unittest
import zipfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('backend', Path(__file__).resolve().parents[1] / 'installer_backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.dest = self.root / 'apps'
        self.dest.mkdir()
        self.uid = patch.object(backend.os, 'geteuid', return_value=1000)
        self.uid.start()

    def tearDown(self):
        self.uid.stop()
        self.temp.cleanup()

    def zip(self, names):
        path = self.root / 'Sample.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            for name in names:
                archive.writestr(name, 'contents')
        return str(path)

    def test_zip_listing_install_and_collision(self):
        path = self.zip(['Demo.app/Resources/name', 'Demo.app/program'])
        self.assertEqual(len(backend.inspect(path)['files']), 2)
        result = backend.install(path, str(self.dest))
        self.assertEqual(len(result['files']), 2)
        self.assertEqual(Path(result['files'][0]).read_text(), 'contents')
        with self.assertRaises(FileExistsError):
            backend.install(path, str(self.dest))

    def test_traversal_and_absolute_paths(self):
        for name in ('../outside', '/outside', 'a/../../outside', 'a\\b'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                backend.install(self.zip([name]), str(self.dest))
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_compressed_tar_executable_and_link(self):
        for extension, mode in (('tar', 'w'), ('tar.gz', 'w:gz'), ('tar.bz2', 'w:bz2'), ('tar.xz', 'w:xz')):
            path = self.root / ('Demo.' + extension)
            with tarfile.open(path, mode) as archive:
                member = tarfile.TarInfo('App/run')
                member.size = 2
                member.mode = 0o6755
                archive.addfile(member, io.BytesIO(b'#!'))
                link = tarfile.TarInfo('App/link')
                link.type = tarfile.SYMTYPE
                link.linkname = 'run'
                archive.addfile(link)
            destination = self.dest / extension
            destination.mkdir()
            result = backend.install(str(path), str(destination))
            program = Path(result['destination']) / 'App/run'
            self.assertEqual(program.stat().st_mode & 0o7777, 0o755)
            self.assertEqual((program.parent / 'link').read_bytes(), b'#!')

    def test_link_escape_rolls_back(self):
        path = self.root / 'Bad.tar'
        with tarfile.open(path, 'w') as archive:
            link = tarfile.TarInfo('escape')
            link.type = tarfile.SYMTYPE
            link.linkname = '../outside'
            archive.addfile(link)
        with self.assertRaises(ValueError):
            backend.install(str(path), str(self.dest))
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_link_parent_rejected(self):
        path = self.root / 'Bad.tar'
        with tarfile.open(path, 'w') as archive:
            link = tarfile.TarInfo('dir')
            link.type = tarfile.SYMTYPE
            link.linkname = 'other'
            archive.addfile(link)
            archive.addfile(tarfile.TarInfo('dir/file'))
        with self.assertRaises(ValueError):
            backend.install(str(path), str(self.dest))

    def test_deb_inspection(self):
        package = self.root / 'package'
        (package / 'DEBIAN').mkdir(parents=True)
        (package / 'DEBIAN/control').write_text('Package: installer-test\nVersion: 1.0\nArchitecture: all\nMaintainer: Test <test@example.com>\nDescription: Test package\n')
        (package / 'usr/share').mkdir(parents=True)
        (package / 'usr/share/example').write_text('test')
        path = str(self.root / 'test.deb')
        subprocess.run(['dpkg-deb', '--build', str(package), path], check=True, stdout=subprocess.PIPE)
        info = backend.inspect(path)
        self.assertEqual(info['name'], 'installer-test')
        self.assertIn('./usr/share/example', info['files'])
        with self.assertRaises(ValueError):
            backend.install(path, '/')

    def test_cli_error_is_plist(self):
        result = subprocess.run(['/usr/bin/python3', str(Path(backend.__file__)), 'inspect', '/no/such/file'], stdout=subprocess.PIPE)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(plistlib.loads(result.stdout)['ok'])


if __name__ == '__main__':
    unittest.main()
