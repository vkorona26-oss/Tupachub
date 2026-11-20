# Tupachub

The site and the payload. GitHub Pages serves both.

```
https://vkorona26-oss.github.io/Tupachub/
```

## One line

```lua
loadstring(game:HttpGet("https://vkorona26-oss.github.io/Tupachub/Exec"))()
```

## Files

| File | Role |
|---|---|
| `index.html` | landing page |
| `assets/` | styles, script, logo |
| `Exec` | loader — fetches `hub.lua`, checks it, runs it |
| `hub.lua` | the hub: UI + modules |

`Exec` tries Pages first, then raw.githubusercontent, then jsDelivr. If one host is
down the script still loads.

## Updating

1. Edit `hub.lua`.
2. Bump `local VERSION` inside it if the change is worth showing in the menu.
3. Commit and push to `main`.

The workflow deploys in about 20 seconds. The loader always fetches `main`, so every
user gets the new payload on their next execution — no reinstall, no new key.

## Supported games

Pet Simulator 99, Pets GO, Grow a Garden, Escape Tsunami for Brainrots.
Detection uses `game.Name` and the marketplace product name, never a hardcoded PlaceId.

## Local preview

```bash
npx serve .
# or
python -m http.server 8080
```

## Licence

Personal use. The payload is plain Lua — read it before you run it.
