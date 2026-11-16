# License alignment checkpoint

User requested the GNU GPL v3 license on 2026-11-17 and explicitly authorized
a conventional commit and push before resuming the native build investigation.

- Commit: 59f6324a642d96b32e2422b5537ad16e2d39cd88.
- Subject: docs(license): add GPL-3.0 to match qflistudio.
- Files: root LICENSE and README.md only.
- LICENSE copied byte-for-byte from D:/MyNewProjects/qflistudio/LICENSE.
- SHA256: 3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986.
- README statement matches the main project and preserves separately licensed content.
- Independent trellis-check passed byte equality, Chinese lint and diff checks.
- Explicit GitHub push completed. git ls-remote confirmed the exact commit on
  refs/heads/ci/native-build-20261117.
- The commit body contains [skip ci] to avoid duplicating the long native builds.
- Main project files were read only. Other local edits and backups were preserved.

The overall native task remains in progress. Run 43937691966 builds 5a83aea,
which predates this license commit. Do not describe it as verification of 59f6324.
