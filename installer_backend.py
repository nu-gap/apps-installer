#!/usr/bin/python3
# Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
"""Installer's noninteractive backend. All responses are XML property lists."""
import argparse
import io
import os
import pathlib
import plistlib
import shutil
import stat
import subprocess
import sys
import tarfile
import zipfile


def run(args):
    process = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if process.returncode:
        raise ValueError(process.stderr.decode(errors='replace') or
                         process.stdout.decode(errors='replace') or 'Command failed')
    return process.stdout


def tool(name):
    for directory in ('/usr/bin', '/bin', '/usr/sbin', '/sbin'):
        path = directory + '/' + name
        if os.access(path, os.X_OK):
            return path
    raise ValueError('Required program is not installed: ' + name)


def kind(path):
    if path.lower().endswith('.deb'):
        return 'deb'
    if path.lower().endswith('.rpm'):
        return 'rpm'
    if zipfile.is_zipfile(path):
        return 'zip'
    if tarfile.is_tarfile(path):
        return 'tar'
    raise ValueError('Unsupported package. Choose ZIP, tar, tar.gz, tar.bz2, tar.xz, DEB or RPM.')


def archive(path, fmt):
    if fmt == 'zip':
        return zipfile.ZipFile(path)
    if fmt == 'deb':
        return tarfile.open(fileobj=io.BytesIO(run([tool('dpkg-deb'), '--fsys-tarfile', path])))
    return tarfile.open(path)


def entries(handle):
    if isinstance(handle, zipfile.ZipFile):
        return [(i.filename, i.file_size, i.is_dir(),
                 'link' if stat.S_ISLNK(i.external_attr >> 16) else 'file', i)
                for i in handle.infolist()]
    return [(i.name, i.size, i.isdir(),
             'file' if i.isfile() or i.isdir() else 'link' if i.issym() else 'special', i)
            for i in handle.getmembers()]


def inspect(path):
    fmt = kind(path)
    result = dict(format=fmt, name=os.path.basename(path), version='', size=os.path.getsize(path))
    if fmt == 'rpm':
        result['files'] = run([tool('rpm'), '-qpl', path]).decode().splitlines()
        result['name'] = run([tool('rpm'), '-qp', '--qf', '%{NAME}', path]).decode().strip()
    else:
        with archive(path, fmt) as handle:
            result['files'] = [e[0] for e in entries(handle)]
        if fmt == 'deb':
            result['name'] = run([tool('dpkg-deb'), '-f', path, 'Package']).decode().strip()
            result['version'] = run([tool('dpkg-deb'), '-f', path, 'Version']).decode().strip()
    return result


def safe_name(name):
    path = pathlib.PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or '\\' in name or '\x00' in name:
        raise ValueError('Unsafe archive path: ' + name)
    return str(path)


def unpack(path, destination, fmt):
    destination = os.path.realpath(destination)
    if not os.path.isdir(destination):
        raise ValueError('The destination must be an existing directory.')
    if os.geteuid() == 0:
        parent = destination
        while True:
            mode = os.stat(parent)
            if mode.st_uid != 0 or mode.st_mode & 0o022:
                raise ValueError('Root installation requires a root-owned destination and ancestors without group/world write access.')
            if parent == '/':
                break
            parent = os.path.dirname(parent)
    folder = os.path.basename(path)
    for suffix in ('.tar.gz', '.tar.bz2', '.tar.xz', '.tgz', '.tbz2', '.txz', '.tar', '.zip'):
        if folder.lower().endswith(suffix):
            folder = folder[:-len(suffix)]
            break
    if folder in ('', '.', '..'):
        raise ValueError('Invalid archive name')
    target = os.path.join(destination, folder)
    with archive(path, fmt) as handle:
        records = entries(handle)
        seen = {}
        for name, size, directory, entry_type, member in records:
            normalized = safe_name(name)
            if normalized == '.' and directory:
                continue
            if normalized == '.' or normalized in seen:
                raise ValueError('Duplicate or invalid archive path: ' + name)
            if entry_type == 'special':
                raise ValueError('Hard links and special files are not supported: ' + name)
            seen[normalized] = (directory, entry_type)
        for name in seen:
            for parent in pathlib.PurePosixPath(name).parents:
                if str(parent) in seen and seen[str(parent)] != (True, 'file'):
                    raise ValueError('Archive entry has a non-directory parent: ' + name)
        os.mkdir(target, 0o755)  # exclusive; never merge with an existing installation
        installed = []
        try:
            links = []
            for name, size, directory, entry_type, member in records:
                name = safe_name(name)
                if name == '.':
                    continue
                output = os.path.join(target, name)
                os.makedirs(os.path.dirname(output), exist_ok=True)
                if directory:
                    os.makedirs(output, exist_ok=True)
                elif entry_type == 'link':
                    value = (handle.read(member).decode() if fmt == 'zip' else member.linkname)
                    resolved = os.path.normpath(os.path.join(os.path.dirname(name), value))
                    if os.path.isabs(value) or resolved == '..' or resolved.startswith('../'):
                        raise ValueError('Symbolic link escapes installation: ' + name)
                    links.append((output, value))
                else:
                    source = handle.open(member) if fmt == 'zip' else handle.extractfile(member)
                    with source, open(output, 'xb') as stream:
                        shutil.copyfileobj(source, stream)
                    mode = member.external_attr >> 16 if fmt == 'zip' else member.mode
                    os.chmod(output, 0o755 if mode & 0o111 else 0o644)
                installed.append(output)
            for output, value in links:
                os.symlink(value, output)
        except BaseException:
            shutil.rmtree(target)
            raise
    return sorted(installed), target


def install(path, destination):
    info = inspect(path)
    fmt = info['format']
    if fmt in ('deb', 'rpm'):
        if os.geteuid() != 0:
            raise ValueError('System packages require administrator authentication.')
        if fmt == 'deb':
            log = run([tool('dpkg'), '--install', path]).decode(errors='replace')
            files = run([tool('dpkg-query'), '-L', info['name']]).decode().splitlines()
        else:
            log = run([tool('rpm'), '-Uvh', path]).decode(errors='replace')
            files = run([tool('rpm'), '-ql', info['name']]).decode().splitlines()
        return dict(files=files, destination='/', log=log)
    files, target = unpack(path, destination, fmt)
    return dict(files=files, destination=target, log='Archive installation completed.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=('inspect', 'install'))
    parser.add_argument('path')
    parser.add_argument('--destination', default=os.path.expanduser('~/Applications'))
    args = parser.parse_args()
    try:
        path = os.path.abspath(args.path)
        result = inspect(path) if args.operation == 'inspect' else install(path, args.destination)
        result['ok'] = True
    except Exception as error:
        result = dict(ok=False, error=str(error))
    sys.stdout.buffer.write(plistlib.dumps(result))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
