# PRD: Vulti Agent UI Redesign

**Date:** 2026-03-12
**Figma:** [Agent Views](https://www.figma.com/design/puB2fsVpPrBx3Sup7gaa3v/Vultisig-App?node-id=68492-75416&m=dev)
**Branch:** `feature/agent-swap-fix`

---

## Overview

Redesign the Vulti Agent UI to match the Figma specifications. The agent feature already has a working backend integration with 18 files (views, view models, services, navigation). This PRD covers the **UI/UX gaps** between current implementation and design.

---

## Current State

| Area | Status | Notes |
|------|--------|-------|
| Chat messaging (text) | Implemented | Basic bubbles, markdown, streaming |
| Transaction proposals | Implemented | Yes/No buttons, swap/send cards |
| Tool call indicators | Implemented | Running/success/error icons |
| Conversations list | Implemented | Swipe-to-delete, connection indicator |
| Password prompt | Implemented | Fast Vault password entry sheet |
| Keysign flow | Implemented | Pairing sheet, tx broadcast |
| Auth service | Implemented | TSS signing, token caching |

---

## Gaps (Figma vs Current)

### GAP 1: Agent Onboarding & Authorization Flow
**Figma sections:** "Vulti Agent on Home", Welcome screen
**Current:** No onboarding. Agent tab just appears when enabled.

**Missing screens:**
- **"New!" tooltip/banner** on agent tab icon on first visit
- **Authorization dialog** — modal with "Authorize Vulti Agent" title, description, "Not now" / "Authorize" buttons, "Learn More" link
- **Welcome screen** — full-screen with blue orb animation, "Welcome to Vulti Agent" title + subtitle, password entry field, "Authorize Agent" button
- **Re-authorize prompt** — periodic re-auth dialog with "Cancel" / "Authorize" buttons on home screen

---

### GAP 2: Session History / Conversations List Redesign
**Figma section:** "Session history"
**Current:** Custom header with "Vultisig" title, connection indicator, menu. Conversation rows with chevrons.

**Changes needed:**
- Replace "Vultisig" header with **hamburger menu icon** (left) + **"Session history" title** (center) + **"+" new chat button** (right, blue circle)
- Add **search bar** variant (search icon + text field) below header
- Simplify conversation rows: just title text, no chevron, no date subtitle
- Remove connection status indicator from header (move to menu or remove)

---

### GAP 3: Chat Header & Navigation
**Figma section:** All chat screens
**Current:** Back chevron (left) + conversation title (center) + menu (right)

**Changes needed:**
- Replace back chevron with **hamburger menu icon** (☰) — opens session history as sidebar/drawer
- Keep conversation title centered
- Keep 3-dot menu (right) but update menu items:
  - "Give Feedback" (with info icon)
  - "Delete Chat Session" (red, with trash icon)

---

### GAP 4: Input Bar — Mic Button & Voice Recording
**Figma sections:** "AI Agent - Initial Screen", "Voice Recording"
**Current:** TextField + send button only.

**Changes needed:**
- Add **microphone button** (right side, blue circle) when text field is empty
- When text is typed, mic button **transforms to send button** (arrow icon, blue)
- Add **conversations history button** (left of input, folder/chat icon) — already exists
- **Voice recording states** (future phase — can defer):
  - Recording UI: red indicator + timer + "Slide to cancel"
  - Hold-to-record gesture on mic button
  - "Transcribed from voice" tag on messages from voice input

---

### GAP 5: Empty Chat State — Starter Cards Redesign
**Figma section:** "AI Agent - Initial Screen"
**Current:** Gradient icon + title + subtitle + 2-column grid of starter cards at top.

**Changes needed:**
- Move blue orb / gradient icon to **center of screen** (vertically centered, above starters)
- Title: "What would you like to do?"
- Subtitle: "I can help prepare swaps, plugin actions, and automation rules."
- Starter chips: horizontal scrolling **pill-shaped chips** at bottom (not grid), each with emoji prefix:
  - "🔌 Show me plugins and what they can do"
  - "💰 I want to earn APY on BTC"
  - "🟢 Send amount to ..."
  - "🔄 Prepare a swap from ETH to BTC"
- Starters positioned **above input bar**, not filling the screen

---

### GAP 6: Agent Action Status System (Icon + Color)
**Figma section:** "Agent Action Color & Icon System"
**Current:** Basic tool call with 3 states (running/success/error) using generic icons.

**New status system with 9 categories:**

| Category | Icon | Color | Examples |
|----------|------|-------|----------|
| 1. Analyzing/Planning | ✳️ gear/sparkle | Gray/muted | ANALYZED FOR 9S, PREPARED EXECUTION PLAN, SIMULATING ROUTE, CALCULATING FEES, SECURITY SCAN, BUILDING TRANSACTION... |
| 2. Awaiting Approval | ⚙️ settings | Teal/cyan | APPROVE 1000 USDT, SWAP 10 ETH → USDC (with route + fee), SEND 10 ETH TO 0xABC... |
| 3. Executing | ↻ arrows | Blue | EXECUTING SWAP, SENDING FUNDS, SAVING REMINDER |
| 4. Success | ✓ checkmark | Green | SWAP COMPLETED (10 ETH → 18,940 USDC), FUNDS SENT |
| 5. Cronjob/Recurring | 🔄 refresh | Teal | RECURRING SWAP ACTIVE, REMINDER |
| 6. Plugin Installed | 🔌 plug | Green | PLUGIN INSTALLED |
| 7. Error | ⚠️ triangle | Red | EXECUTION FAILED, INVALID ADDRESS, NETWORK UNAVAILABLE |
| 8. Balance Display | 📋 clipboard | White/neutral | BALANCE UPDATE (ETH: 0.004, USDC: 5,000) |
| 9. History | ⏱️ clock | Gray | TRANSACTION HISTORY, PLUGIN HISTORY, AUTOMATION RUN |

**Implementation:**
- Create `AgentActionType` enum mapping action names to icon + color
- Each status line: `Icon + UPPERCASED LABEL` on first line, detail text indented below
- Status lines appear inline in chat (not in bubbles), left-aligned
- Use monospaced/all-caps font for status labels

---

### GAP 7: Detailed Step Indicators (Animated)
**Figma section:** "AI Agent - Icons animation"
**Current:** `AgentThinkingIndicator` shows 3 bouncing dots.

**Changes needed:**
- Replace generic dots with **step-by-step progress indicators**
- Each step appears sequentially as agent processes:
  1. ANALYZED FOR 9S
  2. PREPARED EXECUTION PLAN
  3. SIMULATING ROUTE
  4. CALCULATING FEES
  5. SECURITY SCAN
  6. BUILDING TRANSACTION...
- Each step has its own icon (from GAP 6 system)
- Steps appear with fade-in animation as they complete
- Last step shows "..." ellipsis animation while in progress

---

### GAP 8: Transaction Proposal Card Redesign
**Figma section:** "AI Agent States" — Proposing/Approved/Rejected
**Current:** Card with route info + Yes/No buttons inside message area.

**Changes needed:**
- Proposal card uses **colored status lines** (from GAP 6):
  - `⚙️ SWAP 10 ETH → USDC` (teal)
  - `ROUTE: THORCHAIN` (teal, indented)
  - `EST. FEE: 0.001 ETH` (teal, indented)
- Description text below: "Should I execute the swap?"
- **"Yes" button** — pill-shaped, right-aligned, dark background with white text, rounded
- **"No" button** — pill-shaped, right-aligned, dark background with **red text**, rounded
- After approval: shows `✓ SWAP EXECUTED` (green) + "New balance:" with balance lines
- After rejection: "No" appears as user response

---

### GAP 9: Message Timestamps
**Figma section:** "AI Agent - Date & Time stamp"
**Current:** No timestamps on messages.

**Changes needed:**
- Add **date separator** between messages on different days (e.g., "22 Feb, 2026" centered, light text)
- Add **time label** to the right of each message group (e.g., "14:31", "14:32")
- Time font: small, `textTertiary` color
- Date font: small, `textTertiary` color, centered with horizontal lines

---

### GAP 10: Approve Transaction Bottom Sheet
**Figma section:** "Fast Vault - Approve Transaction", "Secure Vault - Approve Transaction"
**Current:** Password prompt sheet exists. Pairing sheet exists.

**Changes needed:**
- **Fast Vault flow:**
  - Bottom sheet with "Approve Transaction" header (centered, teal)
  - X close button (left)
  - Password field with lock icon + "Enter vault password" placeholder
  - Submit button (blue arrow circle, right of field)
  - Alternative: "Confirm with Face ID" button (when biometrics available)
- **Secure Vault flow:**
  - Bottom sheet with QR code for multi-device pairing
  - "Waiting for x devices to connect..." text
  - "Resend notification in 0:30" countdown
  - Device list below: device name + "This device"/"Connected" status + "1 of ∞" counter
- After approval: `✓ TRANSACTION APPROVED` status line in chat (green, uppercase)

---

### GAP 11: Feedback System
**Figma section:** "Give Feedback"
**Current:** Not implemented.

**New screens:**
1. **Feedback Categories Screen** — modal/sheet:
   - Header: "Agent Feedback" + subtitle "Help us improve Vulti Agent performance and accuracy."
   - Category rows with chevron: Incorrect proposal, Wrong execution logic, Took too long, UI confusing, Failed transaction, Other
2. **Feedback Detail Screen** — pushed from category:
   - Back button + "Agent Feedback" title + "Submit" button
   - Selected category label
   - Multiline text field: "Please provide more details"
   - Keyboard opens automatically

---

### GAP 12: Blue Orb / Agent Avatar
**Figma:** All screens show a glowing blue orb as agent identity
**Current:** Unknown (not described in code exploration)

**Needed:**
- **Animated blue orb** asset used in:
  - Welcome screen (large, centered)
  - Empty chat state (medium, centered)
  - Before each agent response (small, left-aligned, as avatar)
  - While agent is thinking/processing
- Orb has a subtle glow/pulse animation
- Can be implemented as Lottie animation or SwiftUI animation with blur/gradient

---

## Task Breakdown

### Phase 1: Core Chat UI Polish (Priority: High)

| # | Task | Size | Files |
|---|------|------|-------|
| 1.1 | Implement Agent Action Status System (enum + views) | M | New: `AgentActionStatusView.swift`, Edit: `AgentChatMessageView.swift` |
| 1.2 | Redesign transaction proposal card with colored status lines | S | `AgentChatMessageView.swift` |
| 1.3 | Add message timestamps (per-message time + date separators) | S | `AgentChatMessageView.swift`, `AgentChatView.swift` |
| 1.4 | Redesign Yes/No approval buttons (pill-shaped, right-aligned) | S | `AgentChatMessageView.swift` |
| 1.5 | Add detailed step indicators (replace bouncing dots) | M | `AgentThinkingIndicator.swift` or new view, `AgentStreamManager.swift` |
| 1.6 | Add blue orb agent avatar (small, before agent messages) | S | `AgentChatMessageView.swift`, asset needed |

### Phase 2: Navigation & Layout (Priority: High)

| # | Task | Size | Files |
|---|------|------|-------|
| 2.1 | Redesign chat header (hamburger menu + title + 3-dot menu) | S | `AgentChatView.swift` |
| 2.2 | Update 3-dot menu items (Give Feedback + Delete Chat Session) | S | `AgentChatView.swift` |
| 2.3 | Redesign conversations list header (hamburger + "Session history" + "+") | S | `AgentConversationsView.swift` |
| 2.4 | Add search bar to conversations list | S | `AgentConversationsView.swift` |
| 2.5 | Redesign empty chat starters (centered orb + horizontal chips) | M | `AgentChatView.swift` |
| 2.6 | Add mic button to input bar (swap with send when typing) | S | `AgentChatView.swift` |

### Phase 3: Onboarding & Authorization (Priority: Medium)

| # | Task | Size | Files |
|---|------|------|-------|
| 3.1 | Create "New!" tooltip banner on agent tab | S | `HomeScreen.swift` or tab bar |
| 3.2 | Create Authorization dialog (modal with Authorize/Not now) | M | New: `AgentAuthorizationView.swift` |
| 3.3 | Create Welcome screen with orb + password entry | M | New or refactor `AgentPasswordPromptScreen.swift` |
| 3.4 | Create Re-authorize prompt dialog | S | New or reuse authorization view |

### Phase 4: Transaction Approval Flow (Priority: Medium)

| # | Task | Size | Files |
|---|------|------|-------|
| 4.1 | Redesign Fast Vault approve bottom sheet (password + Face ID) | M | `AgentChatView.swift`, password prompt |
| 4.2 | Redesign Secure Vault approve sheet (QR + device list) | M | `AgentChatView.swift`, pairing flow |
| 4.3 | Add "TRANSACTION APPROVED" status line after approval | S | `AgentChatMessageView.swift` |

### Phase 5: Feedback System (Priority: Medium)

| # | Task | Size | Files |
|---|------|------|-------|
| 5.1 | Create Feedback Categories screen | M | New: `AgentFeedbackView.swift` |
| 5.2 | Create Feedback Detail screen with text input | S | New: `AgentFeedbackDetailView.swift` |
| 5.3 | Wire feedback to 3-dot menu + backend API | S | `AgentChatView.swift`, `AgentBackendClient.swift` |

### Phase 6: Voice Input (Priority: Low — can defer)

| # | Task | Size | Files |
|---|------|------|-------|
| 6.1 | Implement hold-to-record mic button | L | `AgentChatView.swift`, new speech service |
| 6.2 | Recording UI (timer, slide-to-cancel) | M | New: `AgentVoiceRecordingView.swift` |
| 6.3 | Speech-to-text integration | L | New service |
| 6.4 | "Transcribed from voice" message tag | S | `AgentChatMessageView.swift` |

---

## Size Legend

- **S** = Small (~1-2 hours, single file change)
- **M** = Medium (~2-4 hours, multiple files)
- **L** = Large (~4-8 hours, new feature/service)

## Total Estimates

| Phase | Tasks | Effort |
|-------|-------|--------|
| Phase 1: Core Chat UI | 6 tasks | ~2 days |
| Phase 2: Navigation & Layout | 6 tasks | ~1.5 days |
| Phase 3: Onboarding | 4 tasks | ~1.5 days |
| Phase 4: Transaction Approval | 3 tasks | ~1 day |
| Phase 5: Feedback | 3 tasks | ~1 day |
| Phase 6: Voice (deferred) | 4 tasks | ~3 days |
| **Total (Phase 1-5)** | **22 tasks** | **~7 days** |

---

## Notes

- All new views must use `Theme.colors.*` and `Theme.fonts.*` — no hardcoded values
- All user-facing strings must be localized in all 7 language files
- New `.swift` files must be added to `project.pbxproj` via `/add-xcode-files` skill
- Run SwiftLint after each change
- The blue orb asset needs to be provided by design (Lottie/SVG) or recreated in SwiftUI
