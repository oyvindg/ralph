# Global Baseline Manifest

This folder defines what gets installed into `~/.ralph`.

- `manifest.txt` lists repository `.ralph` paths to install globally.
  - Use trailing `/` for directories (example: `hooks/`, `lib/`).
- Installer script: `install-global.sh`

Default install paths in Ralph:

- Global config baseline: `~/.ralph` (installed by `install-global.sh` or `ralph --setup`)
- Ralph runtime home: `~/.local/share/ralph` (installed by top-level `install.sh`)
- Ralph CLI symlink: `~/.local/bin/ralph` (installed by top-level `install.sh`)

Install (non-destructive):

```bash
.ralph/lib/setup/install-global.sh
```

Install and overwrite existing files:

```bash
.ralph/lib/setup/install-global.sh --force
```
