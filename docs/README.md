# In-repo documentation

Long-form notes for subsystems whose reasoning does not fit in code comments —
ordering constraints, rejected alternatives, and the failure each guard exists to
prevent. Written for whoever changes the code next, human or agent.

One folder per subsystem. Code comments stay the source of truth for *what a type
does*; these pages carry the *why* that spans several types.

| Folder | Subsystem |
|---|---|
| [`passcode-keyshare-encryption/`](passcode-keyshare-encryption/overview.md) | The app passcode and at-rest encryption of key shares. Read before touching anything under `Core/Security/Keyshare/` or `Core/Security/Passcode/`. |

These files are outside the XcodeGen source globs in `VultisigApp/project.yml`
(which scan `VultisigApp/` only), so adding a page here never needs
`make generate`.
