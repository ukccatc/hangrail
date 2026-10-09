# Hangrail

Screenshots on a rail at the top of your screen.

Free and open source. For macOS 14 and later.

Fork of [Tendedero](https://github.com/alejandrobujan/tendedero) by Alejandro Buján — rebranded (required by upstream license: the Tendedero name and icon are not included).

## What it does

Every screenshot hangs on a line just under the menu bar. Rest the pointer at the top edge and the rail glides down. Move away and it tucks away.

| Gesture | Action |
|:--|:--|
| Click | Copy the image |
| Press and hold | Open in Markup |
| Double click | Open in Preview |
| Drag into an app | Send a copy (stays on the rail) |
| Drag into a folder | Keep it (leaves the rail) |
| Drag to Trash / click × | Discard |
| ⌃ ⌥ T | Show or hide the rail |

## Build from source

```sh
git clone git@github.com:ukccatc/hangrail.git
cd hangrail
scripts/build-app.sh
open build/Hangrail.app
```

Requires the Swift toolchain. Xcode is optional.

## Private by design

No account. No network. No analytics. Screenshots stay on your Mac.

## License

MIT for the code. Hangrail name and icon are reserved (see `LICENSE`). Upstream Tendedero name/icon are not used here.
