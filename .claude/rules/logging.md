# Logging Rules

- Never use `print()` for logging. Always use `OSLog` via `Logger`.
- Import: `import OSLog`
- Create logger: `Logger(subsystem: "com.vultisig.app", category: "kebab-case-name")`
- In classes: `private let logger = Logger(subsystem: "com.vultisig.app", category: "my-class")`
- In structs/views: use a file-level `private let logger = Logger(...)` above the type declaration
- Use appropriate log levels: `logger.info()`, `logger.debug()`, `logger.warning()`, `logger.error()`
- Category should be kebab-case and describe the component (e.g., `"http-client"`, `"tx-history-recorder"`)
