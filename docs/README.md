# In-repo documentation

Long-form notes for subsystems whose reasoning does not fit in code comments —
ordering constraints, rejected alternatives, and the failure each guard exists to
prevent. Written for whoever changes the code next, human or agent.

One folder per subsystem. Code comments stay the source of truth for *what a type
does*; these pages carry the *why* that spans several types.

| Folder | Subsystem |
|---|---|
| [`market-widgets/`](market-widgets/overview.md) | Signal Flow visual hierarchy, family layouts, rendering modes, content stress rules and accessibility requirements for the crypto market WidgetKit extension. |
| [`passcode-keyshare-encryption/`](passcode-keyshare-encryption/overview.md) | The app passcode and at-rest encryption of key shares. Read before touching anything under `Core/Security/Keyshare/` or `Core/Security/Passcode/`. |

These files are outside the XcodeGen source globs in `VultisigApp/project.yml`
(which scan `VultisigApp/` only), so adding a page here never needs
`make generate`.
