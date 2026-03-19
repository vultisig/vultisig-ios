---
name: figma
description: Implement UI from Figma designs via MCP. Mandatory property mapping, theme token verification, Auto Layout to SwiftUI translation. Use when implementing or auditing UI against Figma.
---

# Figma Implementation Workflow

## Prerequisites

A Figma MCP server must be connected. Check which one is available:

| MCP Server | Tool prefix | Notes |
|------------|-------------|-------|
| Figma Desktop (community) | `mcp__figma-desktop__` | WebSocket + Figma plugin, no rate limits |
| Official Figma MCP | `mcp__figma__` | OAuth-based, rate-limited (6/month on free plans) |
| Framelink MCP | `mcp__framelink__` | API-key based, filtered output, reduces tokens |

If no Figma MCP is connected, ask the user to connect one before proceeding.

**Figma file key**: `<FIGMA_FILE_KEY>` (provide at runtime or extract from Figma URL)

## Workflow

### Step 1: Fetch Figma Design

Get the design spec (use whichever MCP server is connected):
```text
# Figma Desktop MCP (currently configured)
mcp__figma-desktop__get_design_context(
  fileKey: "<FIGMA_FILE_KEY>",
  nodeId: "<extracted-node-id>"
)
```

Also capture a screenshot for visual reference:
```text
mcp__figma-desktop__get_screenshot(
  fileKey: "<FIGMA_FILE_KEY>",
  nodeId: "<extracted-node-id>"
)
```

**Important**: Select individual components or small sections — large frames cause truncated responses.

### Step 2: Translate Figma Output to SwiftUI

The MCP returns a structured representation (often in React/CSS terms). Translate to SwiftUI:

| Figma / CSS Concept | SwiftUI Equivalent |
|---------------------|-------------------|
| Auto Layout (vertical) | `VStack` |
| Auto Layout (horizontal) | `HStack` |
| Auto Layout (wrap) | `LazyVGrid` / custom flow |
| `gap: 8` | `.spacing(8)` on Stack |
| Fill container (stretch) | `.frame(maxWidth: .infinity)` |
| Hug contents | Natural sizing (no explicit frame) |
| Fixed size | `.frame(width: X, height: Y)` |
| `padding: 16` | `.padding(16)` |
| `border-radius: 12` | `.cornerRadius(12)` or `.clipShape(RoundedRectangle(cornerRadius: 12))` |
| `opacity: 0.5` | `.opacity(0.5)` |
| `box-shadow` | `.shadow(color:radius:x:y:)` |
| `overflow: hidden` | `.clipped()` |
| `position: absolute` | `ZStack` with `.offset()` or overlay |

### Step 3: Create Property Mapping Table

Before writing ANY code, create a mapping table:

| Figma Property | Value | SwiftUI Token | Match? |
|----------------|-------|---------------|--------|
| Background | #1A1A2E | Theme.colors.background | Yes |
| Text color | #FFFFFF | Theme.colors.text | Yes |
| Font size | 16sp | Theme.fonts.body | Yes |
| Corner radius | 12dp | 12 | Yes |
| Padding | 16dp | 16 | Yes |

### Step 4: Implement in SwiftUI

Follow these rules:
- Match Figma EXACTLY — do not approximate values
- Use `Theme.colors.*` and `Theme.fonts.*` when they resolve to the correct Figma values
- If a required color is missing from theme tokens, add a new token in the design system and use `Theme.colors.*`
- Use `PrimaryButton` for all buttons
- Use `.foregroundStyle()` not `.foregroundColor()`
- If the MCP returns localhost image/SVG URLs, download and add to Xcode Asset Catalog — do not reference localhost URLs directly

### Step 5: Theme Token Verification

Check theme files for existing tokens:
```text
VultisigApp/VultisigApp/Core/DesignSystem/
```

Map Figma values to existing theme tokens. Only create new constants if no existing token matches.

### Step 6: Localization

If the design contains user-facing text:
1. Add keys to ALL 7 Localizable.strings files
2. Use `"key".localized` in the SwiftUI view
3. Run `python3 VultisigApp/scripts/sort_localizable.py`

## Figma URL Parsing

Extract `fileKey` and `nodeId` from URL pattern:
- `figma.com/design/:fileKey/:fileName?node-id=:nodeId`
- Convert `-` to `:` in nodeId (e.g., `1-2` → `1:2`)

## Available MCP Tools Reference

### Figma Desktop MCP (currently configured)
- `mcp__figma-desktop__get_design_context` — structured design data (layout, styles, text)
- `mcp__figma-desktop__get_screenshot` — visual screenshot of a node
- `mcp__figma-desktop__get_metadata` — lightweight XML with layer IDs, positions, sizes

### Official Figma MCP (if connected instead)
- `get_design_context` — structured design data (customizable framework output)
- `get_screenshot` — visual screenshot
- `get_variable_defs` — extract design tokens (colors, spacing, typography)
- `get_code_connect_map` — mapping of Figma nodes to code components
- `get_metadata` — lightweight XML metadata

## Implementation Checklist

- [ ] Figma design fetched before writing code
- [ ] Figma output translated from CSS/React to SwiftUI layout concepts
- [ ] Property mapping table created
- [ ] All hex colors matched to theme tokens or documented
- [ ] All dp/sp values matched exactly
- [ ] Corner radii, borders, opacity values matched
- [ ] Theme tokens used where they map to Figma values
- [ ] PrimaryButton used for all buttons
- [ ] .foregroundStyle() used (not .foregroundColor())
- [ ] User-facing strings localized in all 7 files
- [ ] SwiftLint passes

## Rules

- ALWAYS fetch the Figma design before writing any code
- Match Figma EXACTLY — colors, spacing, typography, corner radii, shadows, opacity
- Always translate Figma MCP output (React/CSS representation) into SwiftUI — never copy React/CSS patterns directly
- Use existing theme tokens when they resolve to the correct Figma hex
- Cross-reference Figma component names with existing SwiftUI components before creating new ones
- When modifying strings, update all 7 locale files
- Do not modify unrelated code
- Select small sections of the design — large frames produce truncated/incomplete MCP responses
