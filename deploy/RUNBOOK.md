# Hermes Mobile relay — VPS deploy runbook (katya-claw)

Self-hosted control plane for the iOS app. No HermesPilot account needed — your relay
issues the tokens. Relay + Postgres + Caddy (auto-HTTPS) in Docker; the connector runs
next to your Hermes Agent and bridges jobs over one WebSocket.

## 0. Prerequisites
- VPS with public IP `193.23.201.2`, Docker + Docker Compose plugin installed.
- A domain/subdomain pointing at the VPS (HTTPS is mandatory for iOS).
  `katya-claw.play2go.cloud` already resolves here — you can reuse it or add e.g.
  `hermes.play2go.cloud` with an A record → `193.23.201.2`.
- Hermes Agent already installed on this box (`hermes --version` works — yours is 0.16.0).

## 1. Lay out the stack
```bash
mkdir -p ~/hermes-stack && cd ~/hermes-stack
git clone https://github.com/dylan-buck/Hermes-iOS
# copy the three deploy files (docker-compose.yml, Caddyfile, .env.template) into ~/hermes-stack
cp .env.template .env
```

## 2. Configure `.env`
```bash
# generate secrets
openssl rand -hex 32   # -> INTERNAL_API_KEY
openssl rand -hex 32   # -> CONNECTOR_SETUP_SECRET
openssl rand -hex 16   # -> POSTGRES_PASSWORD
```
Edit `.env` and set:
- `RELAY_DOMAIN=katya-claw.play2go.cloud`  (or your chosen subdomain)
- `PUBLIC_BASE_URL=https://katya-claw.play2go.cloud/v1`  (must end with `/v1`)
- `POSTGRES_PASSWORD`, `INTERNAL_API_KEY`, `CONNECTOR_SETUP_SECRET` = the generated values

## 3. Launch
```bash
cd ~/hermes-stack
docker compose up -d --build
docker compose logs -f caddy   # wait for the TLS cert to be issued
```
Verify:
```bash
curl https://katya-claw.play2go.cloud/v1/health     # -> {"data":{"status":"ok",...}}
```

## 4. Start the connector (host bridge) next to Hermes Agent
```bash
cd ~/hermes-stack/Hermes-iOS/connector
python3 -m venv .venv && source .venv/bin/activate
pip install -e .

export HERMES_COMMAND=$(command -v hermes)
export HERMES_WORKDIR=$HOME            # project dir the agent runs in
# the setup secret is read from the environment (must equal CONNECTOR_SETUP_SECRET in the relay .env):
export CONNECTOR_SETUP_SECRET=<same value as in ~/hermes-stack/.env>
hermes-mobile setup --relay-url https://katya-claw.play2go.cloud/v1
# registers the host and writes connector state. Then install + start the background service:
hermes-mobile service install
hermes-mobile service start
hermes-mobile status          # should show relay connected, host online
```

## 5. Generate a phone pairing code
```bash
hermes-mobile pair-phone
# prints an 8-char code like  ABCD-EF23  (valid 10 min)
```

## 6. Pair the iOS app
Open the Hermes app → "Enter pairing code" → type the 8-char code and the relay URL
`https://katya-claw.play2go.cloud/v1`. The app calls `/v1/phone-pairing/redeem`, gets
tokens, and you're in.

---

### Useful
```bash
docker compose ps
docker compose logs -f relay
docker compose restart relay
hermes-mobile status          # connector health
hermes-mobile pair-phone      # new code anytime
```

### Health/diagnostics
- `GET /v1/health` — relay up
- `GET /v1/version` — relay version
- Connector offline → messages stay "pending"; check `hermes-mobile status` and that the
  WebSocket to `RELAY_DOMAIN` is established.
