# Rescope personal assistant

This folder deploys a dedicated OpenClaw gateway to AWS Lightsail and connects it to:

- ChatGPT/Codex subscription authentication through the interactive device-code flow;
- a dedicated Slack channel through Socket Mode;
- the Rescope repository, its `.agents/skills`, and guarded `scripts/rescope-admin.sh` entry point.

Normal channel messages require an `@Rescope Assistant` mention. `/openclaw <request>` is also available in the allowed channel. No public Slack webhook or OpenClaw gateway port is created; only SSH is open, restricted to the supplied CIDR.

## Architecture and safety boundary

- CloudFormation creates one Ubuntu 24.04 Lightsail instance and one attached static IP.
- OpenClaw `2026.7.1-2` is pinned because it was the npm `latest` stable release on 2026-08-19. Override `OpenClawVersion=latest` only if you accept an unreviewed upgrade at deploy time.
- Slack uses outbound Socket Mode (`xapp-` + `xoxb-` tokens), so the gateway remains bound to `127.0.0.1:18789`.
- Slack DMs are disabled. One channel ID and explicit employee user IDs are allowed.
- Host execution uses OpenClaw's `cautious` policy: allowlisted commands may run; everything else requires approval and fails closed when an approver is unavailable. Elevated and direct bash chat commands are disabled.
- Slack tokens and ChatGPT OAuth credentials are enrolled after deployment and never enter the CloudFormation template, parameters, outputs, or stack events.
- The Rescope Admin CLI remains dry-run by default and retains its own exact apply/rollback confirmations. Do not add production credentials during the initial rollout.

## 1. Deploy Lightsail

Prerequisites: AWS CLI credentials, an SSH public key, and your current public IPv4 CIDR. The helper requires the exact AWS account ID as a guard, imports a dedicated Lightsail key pair if needed, validates the template, and deploys the stack.

```bash
cd personal-assistant

./scripts/deploy.sh \
  --profile <aws-profile> \
  --confirm-account <12-digit-account-id> \
  --ssh-cidr <your-public-ip>/32
```

Get the static IP and wait for cloud-init:

```bash
ASSISTANT_IP="$(aws cloudformation describe-stacks \
  --stack-name rescope-personal-assistant \
  --region eu-west-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicIp`].OutputValue' \
  --output text)"

ssh ubuntu@"$ASSISTANT_IP" 'cloud-init status --wait && openclaw --version'
```

## 2. Create the Slack app

1. In Slack, create an app **from a manifest** and paste [`slack-app-manifest.json`](./slack-app-manifest.json).
2. Under **Basic Information → App-Level Tokens**, create a token with `connections:write`; keep the resulting `xapp-...` value.
3. Install the app to the Rescope workspace and keep the `xoxb-...` bot token.
4. Invite the app to a dedicated channel such as `#rescope-assistant`.
5. Copy the channel ID from its Slack link and copy the stable Slack user IDs for every allowed employee and approver.

The manifest deliberately uses OpenClaw's minimal scope set. Add file/reaction/pin scopes only when a concrete workflow needs them.

## 3. Prepare the Rescope checkout

Use a repository-scoped, read-only GitHub deploy key rather than a personal GitHub login:

```bash
ssh ubuntu@"$ASSISTANT_IP" 'ssh-keygen -t ed25519 -f ~/.ssh/rescope_assistant -N "" -C rescope-assistant'
ssh ubuntu@"$ASSISTANT_IP" 'cat ~/.ssh/rescope_assistant.pub'
```

Add that public key to the Rescope repository as a read-only deploy key. Then configure it on the instance:

```bash
ssh ubuntu@"$ASSISTANT_IP" 'cat >> ~/.ssh/config' <<'EOF'
Host github.com
  IdentityFile ~/.ssh/rescope_assistant
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF

scp scripts/prepare-rescope.sh ubuntu@"$ASSISTANT_IP":/tmp/
ssh ubuntu@"$ASSISTANT_IP" 'chmod +x /tmp/prepare-rescope.sh && /tmp/prepare-rescope.sh'
```

This installs repository dependencies but no Supabase credentials. The OpenClaw workspace points at this checkout, so repo-local `.agents/skills`—including `rescope-admin-cli`—are discovered automatically.

## 4. Enroll ChatGPT and Slack

Copy and run the interactive configuration script. Use stable Slack IDs, not display names:

```bash
scp scripts/configure-instance.sh ubuntu@"$ASSISTANT_IP":/tmp/
ssh -t ubuntu@"$ASSISTANT_IP" \
  'chmod +x /tmp/configure-instance.sh && /tmp/configure-instance.sh \
    --channel-id C12345678 \
    --allowed-user-ids U12345678,U87654321 \
    --approver-user-ids U12345678'
```

The script first shows a ChatGPT device code. Complete that browser flow, then paste the Slack `xapp-` and `xoxb-` tokens into the hidden prompts.

For a shared company assistant, use a company-managed ChatGPT workspace/account rather than a personal account before inviting employees. The OAuth path works with a personal ChatGPT subscription, but usage, retention, offboarding, and account ownership then remain personal.

## 5. Verify in Slack

In the allowed channel:

```text
@Rescope Assistant list the Rescope skills you can use
/openclaw /tools verbose
@Rescope Assistant use the rescope-admin-cli skill to list the DEV matrix options; dry-run only
```

A request that needs a host command should create an approval DM for an approver. Start with read-only/DEV operations. Keep production service-role credentials off the instance until the Slack allowlist, approval routing, Admin CLI dry-run output, and rollback workflow have been reviewed end to end.

## Operations

Dashboard through an SSH tunnel:

```bash
ssh -N -L 18789:127.0.0.1:18789 ubuntu@"$ASSISTANT_IP"
```

Then open `http://127.0.0.1:18789/`. Retrieve the gateway token only over SSH:

```bash
ssh ubuntu@"$ASSISTANT_IP" "sed -n 's/^OPENCLAW_GATEWAY_TOKEN=//p' ~/.openclaw/.env"
```

Check or update OpenClaw:

```bash
ssh ubuntu@"$ASSISTANT_IP" 'openclaw status && openclaw security audit --deep'
ssh ubuntu@"$ASSISTANT_IP" 'npm view openclaw version && sudo npm install -g openclaw@<reviewed-version> && openclaw doctor --fix && openclaw gateway restart'
```

Delete the deployment:

```bash
aws cloudformation delete-stack \
  --stack-name rescope-personal-assistant \
  --region eu-west-1
```

CloudFormation deletion removes the instance and its static IP. Back up `~/.openclaw` first if sessions or configuration must be retained.

## Local validation

```bash
./scripts/check.sh
```

The check validates the shell scripts, Slack manifest, and CloudFormation template. It also installs the pinned OpenClaw release into a temporary home and verifies the generated Slack/security patch with OpenClaw's real schema and SecretRef resolver.
