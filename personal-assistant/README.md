# Rescope personal assistant

- AWS Lightsail in `eu-west-1`, deployed by CloudFormation.
- OpenClaw `2026.7.1-2`, connected to ChatGPT with OAuth.
- Private Slack channel `#rescope-assistant`; Vincent and Johan can request and approve commands.
- Rescope repository cloned read-only with its skills and guarded Admin CLI.
- Gateway is loopback-only; SSH is limited to one `/32` address.
- No Supabase or production credentials are installed.

## Deploy

```bash
cd personal-assistant

./scripts/deploy.sh \
  --profile vincent \
  --region eu-west-1 \
  --confirm-account <aws-account-id> \
  --ssh-cidr <public-ip>/32

ASSISTANT_IP="$(aws cloudformation describe-stacks \
  --profile vincent \
  --region eu-west-1 \
  --stack-name rescope-personal-assistant \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicIp`].OutputValue' \
  --output text)"

ssh -i ~/.ssh/id_ed25519 ubuntu@"$ASSISTANT_IP" \
  'cloud-init status --wait && openclaw --version'
```

## Connect Rescope

- Create a read-only GitHub deploy key with the first commands.
- Add the printed public key to `drift-ai/rescope-transformation-platform`.

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@"$ASSISTANT_IP" \
  'ssh-keygen -t ed25519 -f ~/.ssh/rescope_assistant -N "" -C rescope-assistant'
ssh -i ~/.ssh/id_ed25519 ubuntu@"$ASSISTANT_IP" \
  'cat ~/.ssh/rescope_assistant.pub'

ssh -i ~/.ssh/id_ed25519 ubuntu@"$ASSISTANT_IP" 'cat >> ~/.ssh/config' <<'EOF'
Host github.com
  IdentityFile ~/.ssh/rescope_assistant
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF

scp -i ~/.ssh/id_ed25519 scripts/prepare-rescope.sh \
  ubuntu@"$ASSISTANT_IP":/tmp/
ssh -i ~/.ssh/id_ed25519 ubuntu@"$ASSISTANT_IP" \
  'chmod +x /tmp/prepare-rescope.sh && /tmp/prepare-rescope.sh'
```

## Connect Slack and ChatGPT

- Create the Slack app from `slack-app-manifest.json`.
- Enable Socket Mode, install the app, and invite it to `#rescope-assistant`.
- The script opens ChatGPT OAuth and securely prompts for `xapp-` and `xoxb-` tokens.

```bash
scp -i ~/.ssh/id_ed25519 scripts/configure-instance.sh \
  ubuntu@"$ASSISTANT_IP":/tmp/
ssh -t -i ~/.ssh/id_ed25519 ubuntu@"$ASSISTANT_IP" \
  'chmod +x /tmp/configure-instance.sh && /tmp/configure-instance.sh \
    --channel-id <slack-channel-id> \
    --allowed-user-ids <vincent-id>,<johan-id> \
    --approver-user-ids <vincent-id>,<johan-id>'
```

## Update

- Rescope code and skills update through Git.
- OpenClaw updates through npm, not Git.
- Repository changes do not update the server automatically; rerun the relevant script or CloudFormation deployment.

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@"$ASSISTANT_IP" \
  'git -C ~/rescope-transformation-platform pull --ff-only && \
   cd ~/rescope-transformation-platform && npm ci'

ssh -i ~/.ssh/id_ed25519 ubuntu@"$ASSISTANT_IP" \
  'npm view openclaw version && \
   sudo npm install -g openclaw@<reviewed-version> && \
   openclaw gateway restart'
```

## Verify

```bash
./scripts/check.sh

ssh -i ~/.ssh/id_ed25519 ubuntu@"$ASSISTANT_IP" \
  'openclaw models status && \
   openclaw channels status --probe && \
   openclaw gateway status && \
   openclaw security audit --deep'
```
