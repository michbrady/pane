# Pane design system

Apple's look, Explorer's layout. Only the accent is custom. Layout is in
`docs/DESIGN.md`; this page says which token to use when.

## Accent (`UI/Theme.swift`)
- Default is `system`: Pane follows the Mac's accent color. People can pick
  another in Settings > Appearance.
- Use `.tint` or `Palette.accent` for fills and selection. Never a hex.
- Accent-colored text is `Palette.accentText`. Text on an accent fill is
  `Palette.onAccent`, never fixed white.
- Selection in the list and Navigation pane is the system selection color.
- Folder icons keep their own colors from `NSWorkspace`. Nothing else is tinted.

## Spacing (`UI/Grid.swift`)
- `Space` on a 4 pt grid. 8 pt between related controls, 20 pt window margins.
- Fixed sizes live in `Layout.swift`. Use `Layout.rowHeight` (24) for rows in
  Details, List, and the Navigation pane. Address bar 36, Status bar 24.

## Radii (`UI/Radius.swift`)
- `xs 6` chips, `sm 8` the Address bar field, `row 8` row hover and selection
  fills, `md 12` panels in sheets. Inner radius = outer radius - inset.

## Surfaces (`UI/Surfaces.swift`)
- `Surfaces.field` behind the Address bar field. `Surfaces.hairline` between
  window parts. `Surfaces.cutOpacity` (0.5) for cut items.
- The Address bar row and Status bar use the system `.bar` material. No glass
  on glass: glass belongs to the toolbar, sidebar, and sheets, which the
  system draws.
- Text is `.primary`, `.secondary`, `.tertiary`. No fixed grays.

## Motion (`UI/Motion.swift`)
- Every `withAnimation` and `.animation` uses `Motion`. Reduce Motion becomes a fade.
- Listing a folder and showing search results do not animate. Speed wins.
- Hover never moves the selection. Only a click or a key does.
- Never animate a view's first layout.

## Controls
- Use system `ButtonStyle`s and toolbar items. No rebuilt controls.
- One prominent button per sheet ("Replace" in the conflict sheet is not
  prominent: the safe choice, "Skip", is the default).

## Not tokens
- Window chrome (title bar, tabs, toolbar, sidebar, menus, sheets) stays system.
- Type is system text styles. Body 13 pt, nothing under 10 pt.
