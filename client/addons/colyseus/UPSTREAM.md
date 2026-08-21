# Colyseus Godot SDK provenance

- Upstream: `colyseus/native-sdk`
- Release tag: `godot-v0.17.11`
- Tag commit: `b0da87edb97e2f6333655b8d051f02e8b05d0973`
- Release page: <https://github.com/colyseus/native-sdk/releases/tag/godot-v0.17.11>
- Asset: <https://github.com/colyseus/native-sdk/releases/download/godot-v0.17.11/colyseus-godot-0.17.11.zip>
- Asset size: `89492987` bytes
- SHA-256: `334ea298f80af77089549c06dda89dfcbd98a33d7177a4a8bee9b8e7dacd9b7c`

The release ZIP has `addons/` at its root and was extracted into the Godot
project without modifying the shipped files. The ZIP omits licensing and
release notes, so `LICENSE` and `CHANGELOG.md` were copied verbatim from the
same tag's source archive.

This repository tracks the Windows x86_64 and Android arm64 debug and release
binaries required by the verified desktop and Android prototype targets. The
root `.gitignore` excludes the other platform binaries; re-running the
extraction command restores them when another export target is intentionally
added.

`version.json` is the authoritative packaged version. The upstream asset's
`plugin.cfg` still says `0.17.0`; it is intentionally preserved unchanged.

Reinstall from PowerShell:

```powershell
$archive = Join-Path $env:TEMP 'colyseus-godot-0.17.11.zip'
curl.exe -L --fail `
  'https://github.com/colyseus/native-sdk/releases/download/godot-v0.17.11/colyseus-godot-0.17.11.zip' `
  -o $archive
(Get-FileHash -Algorithm SHA256 $archive).Hash
Expand-Archive -LiteralPath $archive -DestinationPath .\client -Force
```

The printed hash must match the SHA-256 above before extraction.
