# Agent Instructions

This repository is a reusable Terraform module for deploying OpenClaw on AWS Lightsail. Treat the repo root as the module interface that other projects import.

## Primary goals

- Keep the module reusable from other Terraform projects.
- Preserve a reliable remote shell path for a local coding agent.
- Keep OpenClaw reachable through SSH tunneling by default instead of exposing the gateway publicly.
- Keep optional AWS Systems Manager hybrid activation working as a secondary terminal-access path.

## Access model

- Direct SSH is the primary access path. Do not remove SSH support unless explicitly asked.
- The OpenClaw gateway should stay loopback-only by default (`127.0.0.1` on port `18789`) so local clients reach it through an SSH tunnel.
- Do not open the OpenClaw gateway port publicly unless the user explicitly asks for that behavior.
- Static IP support matters because it gives the local agent a stable SSH target.

## Terraform expectations

- Keep the root module self-contained: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, and `startup/`.
- Preserve backwards-compatible inputs and outputs when possible. If you change the module interface, update `README.md` and the example.
- Prefer explicit validations and preconditions for user-facing inputs instead of implicit failure later in apply.
- Avoid changes that would force instance replacement on every plan for normal bootstrap-script edits.

## Bootstrap expectations

- Bootstrap should remain idempotent enough for first-boot provisioning and safe re-runs where practical.
- OpenClaw installation should remain non-interactive by default.
- If changing service installation or onboarding flags, verify that the resulting instance still supports:
  - SSH shell access
  - SSH port forwarding to the OpenClaw gateway
  - optional SSM registration

## Documentation expectations

- Keep `README.md` aligned with the actual module behavior.
- Document any change that affects:
  - required inputs
  - access method
  - security posture
  - post-deploy operator workflow

## Validation workflow

Run these commands after meaningful changes:

```bash
terraform fmt -recursive
terraform validate
terraform -chdir=examples/basic validate
```

If you change provider constraints or the example module wiring, also run:

```bash
terraform init -backend=false
terraform -chdir=examples/basic init -backend=false
```

## Safety and secrets

- Do not hardcode private keys, tokens, or cloud credentials.
- Remember that `openclaw_env_vars` and explicit gateway tokens land in Terraform state; preserve `sensitive` handling.
- Tighten security defaults only when it does not break the core “local agent can still get in” requirement.

## Repository conventions

- `CLAUDE.md` should remain a symlink to this file.
- Keep changes pragmatic and minimal; this is infrastructure code, not a playground for broad refactors.
