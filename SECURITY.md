# Security status

This source snapshot is a local development prototype for evaluation. It does not include production resources, private accounts or provider credentials, and is not certified for public deployment.

Provider keys must remain backend-only and ignored. Do not publish local .env/.secret files, service-account keys, Firebase account exports or private logs. Use your own Firebase project and budgets. The included Firebase example is deliberately fictitious and uses a demo project with localhost emulators.

Known limits: callable App Check is not yet enforced; per-user rate limits do not prevent creation of multiple abusive accounts; operational budgets, production monitoring and a full security review are still required. npm audit reports six moderate indirect-dependency findings after compatible updates removed the critical/high/low findings. Those residual advisories are not silently suppressed or claimed resolved.

The free isolated test suite covers authentication, personal data access, group membership and writing restrictions. Passing it is not a penetration test or proof of absence of vulnerabilities. Never expose Firebase emulator ports to the public internet.
