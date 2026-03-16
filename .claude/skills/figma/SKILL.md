---
name: figma
description: Implement UI from Figma designs via MCP. Mandatory property mapping, theme token verification. Use when implementing or auditing UI against Figma.
---

# Figma Implementation Workflow

## Prerequisites

The Figma MCP server must be connected. If not available, ask the user to connect it before proceeding.

**Figma file key**: `puB2fsVpPrBx3Sup7gaa3v` (Vultisig App)

## Workflow

### Step 1: Fetch Figma Design

Get the design spec:
```
mcp__figma-desktop__get_design_context(
  fileKey: "puB2fsVpPrBx3Sup7gaa3v",
  nodeId: "<extracted-node-id>"
)
```

Also capture a screenshot for reference:
```
mcp__figma-desktop__get_screenshot(
  fileKey: "puB2fsVpPrBx3Sup7gaa3v",
  nodeId: "<extracted-node-id>"
)
```

### Step 2: Create Property Mapping Table

Before writing ANY code, create a mapping table:

| Figma Property | Value | SwiftUI Token | Match? |
|----------------|-------|---------------|--------|
| Background | #1A1A2E | Theme.colors.background | Yes |
| Text color | #FFFFFF | Theme.colors.text | Yes |
| Font size | 16sp | Theme.fonts.body | Yes |
| Corner radius | 12dp | 12 | Yes |
| Padding | 16dp | 16 | Yes |

### Step 3: Implement in SwiftUI

Follow these rules:
- Match Figma EXACTLY — do not approximate values
- Use `Theme.colors.*` and `Theme.fonts.*` when they resolve to the correct Figma values
- For colors not in the theme, use SwiftUI `Color` with exact hex
- Use `PrimaryButton` for all buttons
- Use `.foregroundStyle()` not `.foregroundColor()`

### Step 4: Theme Token Verification

Check theme files for existing tokens:
```
VultisigApp/VultisigApp/DesignSystem/
```

Map Figma values to existing theme tokens. Only create new constants if no existing token matches.

### Step 5: Localization

If the design contains user-facing text:
1. Add keys to ALL 7 Localizable.strings files
2. Use `"key".localized` in the SwiftUI view
3. Run `python3 VultisigApp/scripts/sort_localizable.py`

## Figma URL Parsing

Extract `fileKey` and `nodeId` from URL pattern:
- `figma.com/design/:fileKey/:fileName?node-id=:nodeId`
- Convert `-` to `:` in nodeId (e.g., `1-2` → `1:2`)

## Implementation Checklist

- [ ] Figma design fetched before writing code
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
- Use existing theme tokens when they resolve to the correct Figma hex
- When modifying strings, update all 7 locale files
- Do not modify unrelated code
- Cross-reference Figma component names with existing SwiftUI components before creating new ones
