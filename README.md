# Viewpoint Bath & Shower Effects

Client-side shower and bathtub water and steam effects for **Take A Bath And Shower [SP/MP]** (`TakeABathAndShowerNew`) in Project Viewpoint's first- and third-person cameras.

Includes two selectable shaderpacks:

- **Default + Bath & Shower Effects**, inheriting Viewpoint's Default look.
- **Somber + Bath & Shower Effects**, inheriting Viewpoint's Somber look.

The initial target is Project Zomboid **42.22.2**, Viewpoint **0.1.7 / addon API 1.0**, and TABAS **42.20.15**. Final alignment and multiplayer behavior still need in-game verification.

## Installation and activation

1. Extract `dist/ViewpointBathShowerEffects.zip` into `%USERPROFILE%\Zomboid\Workshop`. The resulting tree must be `Workshop\ViewpointBathShowerEffects\Contents\mods\ViewpointBathShowerEffects\42\mod.info`.
2. Enable **Viewpoint Bath & Shower Effects**, **Viewpoint**, and **Take A Bath And Shower [SP/MP]**, with their existing dependencies. Restart the game so Viewpoint discovers the package.
3. Open **Viewpoint > Advanced > Addons**, activate **Bath & Shower Effects**, and approve the **Lua** and **shaders** permissions.
4. Open **Viewpoint > Graphics** and select **Default + Bath & Shower Effects** or **Somber + Bath & Shower Effects**. Both the addon and one of its shaderpacks must be active.
5. Turn on a shower and inspect it in first and third person. Water appears while its TABAS water object is running. Steam follows the original steam object's opacity and dissipating puffs. Cold showers do not create steam. The TABAS steam-animation option is respected.
6. Fill a supported two-tile bathtub. Its animated water surface rises and falls with the actual fluid amount, remains visible after the tap stops, and disappears when empty. Filling adds a small tap stream. Hot baths produce steam when the temperature is at least 40 °C and the fill ratio exceeds 30%, matching TABAS's bathtub steam rules. The shower-only steam-animation setting does not disable bathtub steam.

Version 0.2.1 changes the addon JAR. Restart the game after updating, and approve the updated addon if Viewpoint requests consent. A Lua reload alone cannot load the new Java bridge.

Only one shaderpack is selected at a time. These variants inherit their base shaders, options and passes; they do not patch the bundled Default or Somber files. Other shaderpacks need their own integration. The effects are absent in the isometric camera, where TABAS keeps its normal rendering.

The addon declares `side=client` and adds no server code or network packets. TABAS remains responsible for multiplayer shower state. Every player who wants the visuals needs this package locally; the server still needs the original bathing mod as usual. Some servers may restrict client mods.

## Known startup issue

Viewpoint 0.1.7 can activate managed shaderpacks before registering their built-in bases. On entering a save this produces `base default: no such pack` or `base somber: no such pack` and falls back to Default. After loading the save, manually reselect the Bath & Shower variant in Viewpoint Graphics.

Addon API 1.0 does not expose a way for this addon to correct that initialization order. The Workshop package has no startup fix. A private, version-checked local patch was tested separately against the installed Viewpoint JAR; it is not bundled or published with this mod. A Viewpoint update can replace that local patch.

## Controls and diagnostics

The selected shaderpack exposes:

- **Shower and bathtub water** and **Shower and bathtub steam** toggles.
- **Water visibility** and **Steam density**, from 0 to 2, default 1.
- **Bath effects quality**: Low, Medium (default), High.
- **Shower head height**, 1.5–2.3 squares, default 1.9, for visual alignment.
- **Full bathtub water height**, 0.35–0.85 squares, default 0.52, and **Bathtub water depth**, 0.10–0.34 squares, default 0.34, for alignment with the basin model.

The addon settings cog has **Diagnostic logs**, disabled by default. When enabled, `[BathShowerEffects]` reports selected effects, effects supplied to the renderer, rendered bathtub count (`bathtubs=`) and snapshot age every ten seconds. The normal activation/version messages also use this prefix. Shader compilation failures appear in Viewpoint's Graphics page and `Zomboid\console.txt`.

At most four nearby shower or bathtub volumes share one budget within 16 squares of the local player. A small selection bias avoids switching between equally distant effects. Discovery uses object/grid-square events and a bounded startup or movement scan of loaded squares. Known shower-effect squares are refreshed every 100 ms to find delayed steam: TABAS creates it with `AddSpecialObject`, which does not emit `OnObjectAdded`. Bathtubs are discovered from their ordinary furniture objects; their two halves are deduplicated and both must still be loaded. The integration reads TABAS's client container getters without changing fluid state, creating containers or sending network messages. It never loads map chunks. Simulation ticks advance the animation clock; paused ticks keep the Lua heartbeat alive without advancing it. A missing heartbeat clears the shader count after two seconds.

## Rendering and limits

Water uses animated procedural spray lines. Steam uses a soft, bounded noise volume. Both are clipped against the scene depth. Their positions follow the shower square and facing; effects are only considered on the local player's floor and on squares the game marks as potentially visible.

Bathtub water is a horizontal rounded surface centered on the actual pair of furniture squares, oriented in all four facings. Its height and footprint vary continuously with the fill ratio. Water stains tint the surface, and a separate low steam volume rises over hot water. The initial basin shape approximates standard two-tile TABAS bathtubs. Custom basin shapes and one-tile tubs are not covered; unsupported or incomplete pairs are skipped. The surface does not add real reflection or refraction, and model-specific alignment still needs in-game verification.

The surface reads TABAS's synchronized final water color, which includes bath salts and stains. This covers Lavender, Citrus, Floral, Forest, Herb and Rose salts, as well as other colors supplied by TABAS. While the final color is unavailable, registered salt definitions provide a fallback; absent or malformed colors retain the normal water rendering. The final synchronized tint is not dirtied a second time. Color changes are sampled with the existing 100 ms client update, without adding network traffic or changing salt benefits, temperature or fluid amounts. Steam and the tap stream retain their normal colors.

The additional pass runs at **final**, after Somber's ink calculation in `post.frag`. It does not write depth or normals, so the new water and steam do not generate black ink outlines. Existing scene outlines remain visible behind transparent effects. Illumination is approximated from the shower square's light level.

These effects are an independent visual approximation, not a conversion of TABAS's original sprites. They do not cast shadows, appear in reflections, refract glass, or add droplet collisions. Occlusion through transparent glass depends on the depth Viewpoint exposes. Fine positioning, low-resolution antialiasing and the view from inside individual shower models require in-game checks. The first local player is the supported camera; split screen is not supported.

Original TABAS water consumption, temperature, sounds, hygiene, character animations and network behavior remain game-managed. This package reads the existing `ShowerWater` and `ShowerSteam` objects and does not modify or transmit them. No original model, texture or shader assets are redistributed.

## Reproducible build and checks

With JDK 25 installed:

```powershell
./tools/Build.ps1 -JdkDir 'C:\path\to\jdk-25' -ViewpointJar 'C:\path\to\Viewpoint.jar'
```

The script extracts only `viewpoint.api.*` as a compilation reference, builds with `--release 17`, and keeps the API outside the shipped JAR. Each shaderpack declares only its new bath pass; Viewpoint inherits the existing passes and targets from its base. Listing base passes again would redefine them and require all their properties. The shared shader source is copied into both packages. Validate against a new Viewpoint build before distributing an update.

Run validation with JDK 25, Python with `lupa`, and the installed game's JAR:

```powershell
./tools/Test.ps1 -JdkDir 'C:\path\to\jdk-25' -ViewpointJar 'C:\path\to\Viewpoint.jar' -GameJar 'C:\path\to\projectzomboid.jar'
```

Checks cover invalid snapshots, the four-shower cap, stale snapshots, camera changes, disabling, discovery, opacity, pause, visibility, unload/reload and Lua hot reload. A hidden OpenGL context compiles and renders all twelve quality/toggle combinations and checks localized output, wall occlusion, world-origin shifts and frozen animation. The actual PZ Lua compiler checks the client script. Packaging checks verify Java 17 bytecode, API isolation, inherited pass lists, matching files and the install ZIP structure.

The installed Viewpoint shaderpack loader also checks that both variants load, retain their base passes and targets exactly once, and resolve inherited shader files. This loader check uses renderer classes only in the development tool, never in the shipped addon. The Java/OpenGL checks run outside the game. They do not establish in-game alignment, multiplayer correctness or a GPU performance budget.

## In-game acceptance checks

- In-game testing so far covers running showers. Bathtub support is implemented and passes automated logic and OpenGL checks, but its alignment has not yet been verified in-game. For showers, check all four orientations, water start/stop, and hot-steam dissipation.
- For bathtubs, compare empty, low, half and full levels with the TABAS fluid tooltip. Fill and drain in all four orientations. Stop filling and confirm the surface remains while the tap stream stops. Compare cold water, hot water at 40 °C with more than 30% fill, and cooling below 40 °C. Check an occupied bath, dirty water and both halves loading separately in multiplayer.
- Add each bath-salt type and compare the basin color with the original TABAS view. Check stained salt water and drain/refill with plain water so no previous tint remains. Logic and offscreen rendering tests cover tint propagation, fallback colors and avoiding duplicate dirt coloring; the in-game appearance remains to be checked.
- Toggle the TABAS steam option and each shaderpack control. Compare both shaderpack variants, including Somber with strong ink outlines.
- Move the camera quickly, stand inside the spray, pause, switch cameras, and put a wall or floor between the camera and shower.
- Leave and return to a loaded area; join a world with a shower already running. Remove a shower and confirm no effect remains.
- In multiplayer, observe a second player switching the shower on and off. Verify the visuals without adding this addon to the server.
- Compare Viewpoint's Performance page with zero, one and four showers; watch frame-time spikes and memory over repeated visits. These measurements remain pending.

## Documentation

Implementation follows the [minimal addon](https://docs.projectviewpoint.org/start/getting-started.md), [Lua exports](https://docs.projectviewpoint.org/api/lua-exports.md), [shader values](https://docs.projectviewpoint.org/api/shader-values.md), and [Shaderpack passes](https://docs.projectviewpoint.org/shaderpacks/passes-and-inputs.md) documentation. It does not use the planned draw-callback API or Viewpoint internals.

