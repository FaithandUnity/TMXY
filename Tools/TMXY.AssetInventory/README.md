# TMXY.AssetInventory

Owner: P2-12 full installed-client asset inventory.

`tmxy_asset_inventory` consumes a frozen TSV projection of the client Manifest and scans the
headerless `qtx`, `sm`, `skem`, `anim`, and `ter` families with the production P1 readers. It
indexes all recognized Package objects once, retains duplicate Package candidates, and reports
equivalent or divergent descriptor variants instead of silently choosing a historical copy.

The executable reads the installed client and Package files but never writes them. One compact
JSON record is written to standard output for every TSV row. ZIF and audio validation are added
by `New-FullAssetInventory.ps1`, which owns the complete P2-12 report and ignored JSONL catalog.

```text
tmxy_asset_inventory <client-root> <manifest-tsv>
```
