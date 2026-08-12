# Secrets
Secrets are things like passwords, API keys, API tokens, etc..
In some cases, such as Google Firebase or RevenueCat, you DO have an API key or similar provided that we can't avoid including in the app.

For things like API keys to LLM services - or really any service that might cost us money - as well as any time we are capturing a password from a user and storing it, these things must always be stored in an appropriate way.

- For macOS and iOS apps that we make, this almost always means storing in the Keychain
- NEVER store secrets in a text file
- NEVER store secrets in source code or in any repo
- NEVER store secrets in plain text elsewhere
- NEVER pass secrets in via an environment variable
