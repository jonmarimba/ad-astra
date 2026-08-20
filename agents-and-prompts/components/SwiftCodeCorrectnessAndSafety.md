# Swift Code correctness and safety
Code safety and correctness are of paramount importance.

- NEVER use force unwrapping or try? without explicit approval by the user.
- WARNING `Task { ... }` will eat thrown errors. ALWAYS handle them.
- NEVER create a custom `Equatable` conformance with a function that simply compares identifiers. Equality is not the same as Identity.

## Swift code smells
- Beware of `.first()`, which is often used as a lazy way to reference "the" entry when there will often be only one. This tends to lead to bugs later on when the result starts returning more than 1 item.
