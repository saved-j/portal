# Portal 1.01a — single frozen series

One snapshot of the product, cut into path-disjoint groups. No group edits what another
group edited: the union is exactly `git diff 5b4d0669..b4d60750`, so applying the
groups in any order gives the same tree.

- base (upstream FlClashX): `5b4d0669cd0105a7eb41078b17c36944bde7f044`
- product head: `b4d60750b1e5a25f32aea715c4f708acaf638ea3`
- product tree (pipeline excluded): `963193fb6b4ab9ff12dcd129fd7a3bdec9cf0650`
- apply mode: `git apply` (not `git am` — these are plain diffs, binaries included)
- total size: 17.7 MB

The live series does not contain `pipeline/` itself: a snapshot cannot include the file that
describes it. That is why verification strips `pipeline/` from both sides.

## Groups

| patch | size |
|---|---|
| `patches/01-android-shell.patch` | 1.6 MB |
| `patches/02-core-xray.patch` | 8.9 MB |
| `patches/03-ui-dashboard.patch` | 0.1 MB |
| `patches/04-ui-profiles.patch` | 0.1 MB |
| `patches/05-l10n.patch` | 0.3 MB |
| `patches/06-branding-icons.patch` | 6.6 MB |
| `patches/07-desktop-product-name.patch` | 0.0 MB |
| `patches/08-docs.patch` | 0.1 MB |
| `patches/09-misc.patch` | 0.0 MB |

## Apply

```bash
./apply.sh 1.01a apply /path/to/worktree   # materialise a working copy on a fresh base
```

## Verify (the only proof that counts)

```bash
./apply.sh 1.01a verify
# OK: 9 group(s) reproduce the committed product tree (963193fb…)
```

The check clones the base, applies every group, commits, and compares tree hashes —
exact equality, not a file walk. Binaries round-trip because every group is generated with
`git diff --binary`.
