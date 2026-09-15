# App icon

The source is [BatteryBar.icon](BatteryBar.icon), an Icon Composer package with three editable SVG layers: the top strip, sage battery, and lightning bolt. The three dots are on the left. Each layer has a 1024 × 1024 canvas. The background color and material settings are in `icon.json`.

SVG supplies the shapes. Icon Composer supplies lighting, depth, and appearance variants. The layers have no baked shadows or outer mask. macOS applies those effects. See [Apple's Icon Composer guide](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

`make build` compiles the layered icon when Xcode 26 or later is selected. Command Line Tools and older Xcode versions use the tracked [flat PNG](AppIcon.png). Public releases require the layered icon. Both paths include a complete `.icns` fallback for older macOS versions.

To edit the icon:

1. Edit the SVG files under `BatteryBar.icon/Assets`, or open `BatteryBar.icon` in Icon Composer to adjust materials. Keep at most four groups.
2. With [Inkscape](https://inkscape.org/) installed, run `python3 scripts/export-icon.py` from the repository root. This updates [AppIcon.svg](AppIcon.svg) and the PNG fallback from the same layers.
3. Run `make build` and `bash scripts/test-release.sh`. Check the icon at small sizes and in default, dark, and mono appearances on macOS 27. The macOS 26 CI job saves the compiled icon as an artifact for local checks.

Inkscape is needed only to update the artwork. Normal builds use Apple's tools and the tracked fallback. An image-generation concept guided the design; the final artwork is editable SVG. The [concept prompt](concept-prompt.txt) is saved for reference.

## Repository preview

[SocialPreview.svg](SocialPreview.svg) uses the existing app icon for GitHub's link preview. To update its [PNG](SocialPreview.png), run:

```bash
/Applications/Inkscape.app/Contents/MacOS/inkscape artwork/SocialPreview.svg --export-type=png --export-filename=artwork/SocialPreview.png
```

Upload the PNG under **Repository Settings → General → Social preview**. It uses GitHub's recommended 1280 × 640 size and must remain under 1 MB. See [GitHub's preview guide](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview).
