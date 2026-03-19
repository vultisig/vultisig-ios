---
name: logging-guide
description: OSLog logging conventions — Logger setup, log levels, category naming, and migration from print().
---

# Logging Guide

## Overview

All logging in the codebase uses Apple's `OSLog` framework via `Logger`. Never use `print()` for logging.

## Reference Implementation

See `VultisigApp/VultisigApp/Core/Networking/HTTPClient.swift` for the canonical example.

## Setup

```swift
import OSLog

// In a class:
class MyService {
    private let logger = Logger(subsystem: "com.vultisig.app", category: "my-service")
}

// In a struct or View (file-level, above the type):
private let logger = Logger(subsystem: "com.vultisig.app", category: "my-view")

struct MyView: View { ... }
```

## Convention

| Item | Rule |
|------|------|
| Subsystem | Always `"com.vultisig.app"` |
| Category | Kebab-case, describes the component (e.g., `"http-client"`, `"tx-history-recorder"`, `"home-screen"`) |
| Access | `private let logger` — never expose loggers publicly |

## Log Levels

| Level | Usage | Example |
|-------|-------|---------|
| `logger.debug()` | Verbose info for development | `logger.debug("Headers: \(headers)")` |
| `logger.info()` | Normal operational events | `logger.info("Cleaned up \(count) old transactions")` |
| `logger.warning()` | Recoverable issues | `logger.warning("Request cancelled")` |
| `logger.error()` | Failures that need attention | `logger.error("Failed to load: \(error)")` |

## Migrating from print()

1. Add `import OSLog` (alphabetical order with other imports)
2. Add the logger property (class) or file-level constant (struct/View)
3. Replace `print("ClassName: message \(value)")` with the appropriate log level
4. Drop the class name prefix from the message — OSLog's category handles identification
5. Choose the right level: errors → `.error()`, info/status → `.info()`, debug data → `.debug()`

## Anti-patterns

```swift
// BAD: print()
print("MyService: Failed to save: \(error)")

// BAD: Redundant class name in message
logger.error("MyService: Failed to save: \(error)")

// GOOD
logger.error("Failed to save: \(error)")
```
