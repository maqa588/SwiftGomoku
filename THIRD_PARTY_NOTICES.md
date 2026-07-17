# Third-Party Notices

## Rapfi

Swift Gomoku bundles an unmodified Apple Silicon build of
[Rapfi](https://github.com/dhbloo/rapfi), a Gomoku/Renju engine distributed
under the GNU General Public License version 3.

- Upstream commit: `3aedf3a2ab0ab710a9f3d00e57d5287ceb864894`
- Upstream description: `250615-20-g3aedf3a`
- Binary version: `0.43.02 (clang++ 21.0.0 on Apple NEON)`
- Target: macOS ARM64 with NEON
- Binary SHA-256: `01c815748c9d3cb4f2a621f446b2595f6b4a42ccb34043ba4cbd43afe9017e63`
- Corresponding source: <https://github.com/dhbloo/rapfi/tree/3aedf3a2ab0ab710a9f3d00e57d5287ceb864894>

The binary was built from that source using Rapfi's ARM64 Clang/NEON CMake
configuration. It is included without source modifications. Rapfi's complete
GPLv3 license and upstream author list are reproduced in `LICENSE` and in the
application bundle.

## piskvork_renju

Swift Gomoku's Piskvork/Renju protocol behavior and parts of its interaction
design were informed by [wind23/piskvork_renju](https://github.com/wind23/piskvork_renju),
which is also distributed under GPLv3. Swift Gomoku does not bundle its binary.
