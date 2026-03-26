# OTCapital — South African Wealth Management Platform

**OTCapital** is an open-source personal finance and wealth management platform built for South Africa, with full support for global markets. Built on Rails 7.2 with Hotwire, it connects to South African banks via [Stitch Money](https://stitch.money) open-banking, as well as Plaid, Enable Banking, and SimpleFin for international accounts.

<b>Community: [Discord](https://discord.gg/36ZGBsxYEK) • [Issues](https://github.com/khayaai/otcapital/issues)</b>

---

## Key Features

- **South Africa-first** — ZAR as default currency, Stitch open-banking integration (FNB, ABSA, Standard Bank, Nedbank, Capitec, Discovery Bank, Investec, TymeBank, and more)
- **Global support** — Plaid (US/CA), Enable Banking (EU/UK), SimpleFin, manual CSV imports
- **Switch modes** — per-family toggle between SA mode (ZAR + Stitch) and Global mode (USD + Plaid/Enable Banking)
- **Full financial picture** — checking, savings, credit cards, investments, crypto, loans, properties
- **AI assistant** — OpenAI-compatible financial chat
- **Self-hostable** — Docker Compose, AGPLv3 license

---

## Quick Start (South Africa)

```sh
git clone https://github.com/khayaai/otcapital.git
cd otcapital
cp .env.example .env
# Set STITCH_CLIENT_ID and STITCH_CLIENT_SECRET (get at https://stitch.money)
bin/setup
bin/dev
```

Visit http://localhost:3000. Register and connect your first SA bank account via **Settings → Connected Accounts → Stitch**.

---

## Local Development

### Requirements

- Ruby (see `.ruby-version`)
- PostgreSQL ≥ 9.3
- Redis ≥ 5.4

### Setup

```sh
cp .env.local.example .env.local
bin/setup
bin/dev

# Optional: load demo data
rake demo_data:default
```

Log in with `user@example.com` / `Password1!` after loading demo data.

---

## Self-Hosting

OTCapital can be [self-hosted with Docker](docs/hosting/docker.md).

Required environment variables:

| Variable | Description |
|---|---|
| `SECRET_KEY_BASE` | Rails secret key |
| `DATABASE_URL` | PostgreSQL connection string |
| `REDIS_URL` | Redis connection string |
| `MARKET_MODE` | `sa` (default) or `global` |
| `STITCH_CLIENT_ID` | Stitch open-banking client ID |
| `STITCH_CLIENT_SECRET` | Stitch open-banking client secret |

See `.env.example` for the full list.

---

## License and Attribution

OTCapital is distributed under the [AGPLv3 license](LICENSE).

This project is a fork of [Maybe Finance](https://github.com/maybe-finance/maybe) (archived) and its community fork [Sure](https://github.com/we-promise/sure). OTCapital is **not affiliated with or endorsed by** Maybe Finance Inc.

- "Maybe" is a trademark of Maybe Finance Inc. — not used here.
- Forked under AGPLv3 — all modifications remain open-source.
