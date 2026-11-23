# Installer

A GNUstep package installer using the original Gorm interface.

Build with `make` in your configured GNUstep environment. Runtime dependencies
are Python 3 (`/usr/bin/python3`), and, for administrator authentication, PolicyKit
(`/usr/bin/pkexec`) with a desktop authentication agent. Debian packages require
`dpkg`/`dpkg-deb`; RPM packages require `rpm`.

Open a package through Document → Open (or `Installer -NSOpen /path/to/package`).
Supported formats are ZIP, tar, tar.gz/tgz, tar.bz2/tbz2, tar.xz/txz, DEB and RPM.
The `.pkg` extension is accepted only when its contents are a supported archive;
Apple Installer packages and arbitrary package scripts are not supported.

* **Archive** lists every archive entry, including directories.
* **Info** shows package details. Set **Location** to the installation directory.
* **Install** installs archives into a new subdirectory named after the archive.
  The default location is `~/Applications`. Existing installations are never
  merged or overwritten. Executable bits and safe relative symbolic links are
  preserved; ownership, setuid/setgid bits, hard links and special files are not.
* **Install as Root**, in the confirmation dialog, authenticates through
  PolicyKit. Only the backend runs as root; the GUI stays under your account.
  For root archive installation, the destination must already exist and it and
  its ancestors must be owned by root without group/world write access.
* DEB/RPM packages install system-wide through `dpkg --install` / `rpm -Uvh`.
  Authentication is requested automatically. These tools can run package scripts
  and upgrade existing packages. Install only packages you trust. Dependencies
  are checked by the package manager; they are not downloaded automatically.
* **Installed** lists paths from the last successful install of this package
  path. Receipts persist in GNUstep user defaults. They are historical records,
  not a live filesystem audit, and do not include untracked files created by
  package scripts. This control replaces the previously unimplemented Delete
  action; uninstall is not provided.

Operations run off the GUI thread. Authentication cancellation, unsupported
formats, unsafe archive paths, missing tools and installation failures are
reported. Archive extraction failures remove the new installation folder.
Native package-manager failures can leave partial system changes; resolve these
with the system package manager. Do not close the application during installation.

Run regression tests with `python3 -m unittest discover -s Tests -v`.
