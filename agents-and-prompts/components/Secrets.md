# Secrets
Secrets are things like passwords, API keys, API tokens, etc. In some cases, such as Google Firebase or RevenueCat, you DO have an API key or similar provided. We can't avoid including it in the app.

Things like API keys to LLM services must always be stored in an appropriate way. The same goes for keys to really any service that might cost us money. The same applies any time we are capturing a password from a user and storing it.

- For macOS and iOS apps that we make, this almost always means storing in the Keychain
- NEVER store secrets in a text file
- NEVER store secrets in source code or in any repo
- NEVER store secrets in plain text elsewhere
- NEVER pass secrets in via an environment variable
