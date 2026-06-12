# Hermes Agent — iOS

Native SwiftUI client for [Hermes](https://github.com/dylan-buck/hermes), an AI agent that runs on your computer. The app connects to your Mac over a self-hosted relay, giving you a full chat interface with real-time streaming, tool activity, and extended thinking — right from your iPhone.

---

## How it works

```
iPhone App  ──HTTPS──►  Relay (your VPS)  ◄──WS──  Connector  ──►  Hermes Agent (your Mac)
```

1. **Relay** — a lightweight FastAPI service you host on any VPS. Issues JWT tokens, queues jobs, and streams SSE events back to the phone.  
2. **Connector** (`hermes-mobile`) — a Python bridge that runs beside Hermes on your Mac, receives jobs from the relay over WebSocket, and invokes the agent.  
3. **iOS app** — pairs with the relay via QR code or 8-char pairing code, then talks to the agent through the relay in real time.

---

## Features

- 💬 **Real-time chat** with token-by-token streaming via SSE  
- 🧠 **Extended thinking** — configurable thinking budget (low / medium / high)  
- 🔧 **Tool activity feed** — see exactly what the agent is doing in real time  
- 📷 **Image attachments** — send photos directly to the agent  
- 🎤 **Voice input** — dictate messages with on-device speech recognition  
- 📋 **Session history** — browse and revisit past conversations  
- 🧬 **Memory, Skills, Profiles, Tasks, Insights, Files** — all agent state at a glance  
- 🔒 **Self-hosted** — your relay, your data; no third-party cloud  
- 🌑 **Dark mode only** — purpose-built dark UI with a custom design system  

---

## Requirements

| | |
|---|---|
| iOS | 17.0+ |
| Xcode | 15+ |
| Swift | 5.10 |
| Server | VPS with Docker + Docker Compose |
| Agent | Hermes 0.16.0+ |

---

## Getting started

### 1. Deploy the relay

See [`deploy/RUNBOOK.md`](deploy/RUNBOOK.md) for the full step-by-step. The short version:

```bash
# On your VPS
mkdir -p ~/hermes-stack && cd ~/hermes-stack
# copy docker-compose.yml, Caddyfile, .env from the deploy/ folder
cp .env.template .env   # fill in RELAY_DOMAIN, secrets, etc.
docker compose up -d --build
```

The stack: **Relay** (FastAPI) + **Postgres 16** + **Caddy** (auto-TLS).

### 2. Start the connector on your Mac

```bash
pip install hermes-mobile          # or: pip install -e ./connector
export CONNECTOR_SETUP_SECRET=<from .env>
hermes-mobile setup --relay-url https://your-relay.example.com/v1
hermes-mobile service install && hermes-mobile service start
hermes-mobile status               # → relay connected, host online
```

### 3. Build & run the iOS app

```bash
# Generate the Xcode project (requires XcodeGen)
brew install xcodegen
xcodegen generate

# Open in Xcode
open HermesAgent.xcodeproj
```

Set your Development Team in Xcode → Signing & Capabilities, then run on your device.

### 4. Pair

```bash
# On your Mac
hermes-mobile pair-phone
# Prints:  ABCD-EF23  and a QR code (valid 10 min)
```

Open the app → scan the QR or enter the relay URL + 8-char code → **Pair**.

---

## Project structure

```
HermesAgent/
├── App/
│   ├── HermesAgentApp.swift      # Entry point, RootView phase switch
│   └── AppState.swift            # Global observable state
├── API/
│   ├── RelayClient.swift         # Auth, token refresh, request signing
│   ├── RelayAPI.swift            # REST endpoints
│   ├── AgentAPI.swift            # Agent-specific endpoints (sessions, memory…)
│   ├── SSEClient.swift           # Server-Sent Events streaming
│   ├── RelayModels.swift         # Codable response types
│   └── RelaySessionStore.swift   # Keychain persistence
├── Features/
│   ├── Chat/                     # Chat UI + streaming view model
│   ├── Home/                     # Dashboard with menu + recent sessions
│   ├── Pairing/                  # QR scanner + code entry
│   └── Sections/                 # Tasks, Skills, Memory, Insights, Profiles, Files, Settings
└── Theme/
    └── Theme.swift               # Design tokens (colors, fonts, shapes)

deploy/
├── docker-compose.yml            # Relay + Postgres + Caddy stack
├── Caddyfile                     # Reverse proxy + auto-TLS config
├── hermes-bridge.py              # Connector entry point
└── RUNBOOK.md                    # Full deploy guide
```

---

## Architecture notes

- **`@Observable` + `@Environment`** — state flows top-down; no Combine, no Redux.
- **SSE streaming** — `ChatViewModel` opens a server-sent-events stream per job and reconciles with the server after completion to guarantee consistency even if events are missed.
- **Keychain-backed sessions** — pairing tokens survive app reinstalls; `RelayClient` handles JWT refresh automatically.
- **XcodeGen** — the Xcode project is generated from `project.yml`. Edit `project.yml`, not `.pbxproj`.

---

## License

Private / proprietary. All rights reserved.
