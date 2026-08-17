# Contributing to PhotoSuite

Thank you for contributing. PhotoSuite is native macOS software with an
offline core and immutable originals. Keep changes small, reviewable,
and correct for Apple silicon and macOS 15 or later.

## Before you start

1. Read the project plan and the parity matrix. Do not describe planned
   work as implemented or as Lightroom-compatible.
2. Open or discuss a proposal before major architecture, dependency, or
   file-format changes.
3. Do not add Adobe code, assets, presets, proprietary documentation,
   private catalog data, or material without a redistribution right.
4. Do not add credentials, personal photographs, personal metadata, or
   location data to the repository.

## Change requirements

- Keep original image bytes immutable.
- Keep import, catalog, edit, preview, and export usable without a
  network connection unless a separately labelled optional feature needs
  one.
- Use Apple-native APIs. Do not introduce Electron or Mac Catalyst.
- Add tests for production behaviour and update user, support, security,
  license, SBOM, and parity documents when the change affects them.
- Record each new dependency and its SPDX license identifier before it
  is merged. Follow docs/DEPENDENCY_POLICY.md.
- Use the MPL 2.0 source-file notice for new covered source files:

  ```text
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  ```

## Developer Certificate of Origin

Every commit must include a DCO sign-off:

```text
Signed-off-by: Your Name <your.email@example.com>
```

Use `git commit -s`. By signing off, you certify the Developer
Certificate of Origin, version 1.1:

```text
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.
1 Letterman Drive
Suite D4700
San Francisco, CA, 94129

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I have
    the right to submit it under the open source license indicated in
    the file; or

(b) The contribution is based upon previous work that, to the best of
    my knowledge, is covered under an appropriate open source license
    and I have the right under that license to submit that work with
    modifications, whether created in whole or in part by me, under the
    same open source license (unless I am permitted to submit under a
    different license), as indicated in the file; or

(c) The contribution was provided directly to me by some other person
    who certified (a), (b) or (c) and I have not modified it.

(d) I understand and agree that this project and the contribution are
    public and that a record of the contribution (including all personal
    information I submit with it, including my sign-off) is maintained
    indefinitely and may be redistributed consistent with this project
    or the open source license(s) involved.
```

## Review

A maintainer must review each change. Review checks include scope,
tests, offline behaviour, source and dependency license compliance,
security effect, support-matrix accuracy, and SBOM effect. A review can
request changes or reject a contribution.
