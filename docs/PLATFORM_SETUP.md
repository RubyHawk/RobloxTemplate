# Published platform setup

The repository's permanent private sandbox is configured in `sandbox.config.json`. Create another experience only when starting a genuinely separate released game.

## Roblox

- Keep the sandbox universe/place IDs in `sandbox.config.json`; the launcher injects them into generated configuration.
- Create a Roblox community owned by the intended creator account and add its ID to `TemplateConfig`.
- Enable Chat & Voice Groups APIs for native cross-server chat and accept Roblox's communication terms.
- Create the Extended Offline Earnings game pass and any direct developer products; enter their IDs in configuration.
- Create notification strings for daily reward and offline earnings. Create a least-privilege Open Cloud key only when deploying the worker.
- Add the Discord server as an experience Social Link. In-game UI may say “Community link on the game page” but must not contain the URL or invite code.
- Upload audio you own or are licensed to use, record its source/license, and fill the audio manifest.
- Keep Studio DataStore access pointed away from production. Test teleports and notifications in the Roblox client, not Studio.

## Discord and guilds

- Discord verification and guilds are intentionally disabled. The interfaces reserve no external identity data by default.
- When enabled later, use one-time link codes, minimal Discord scopes, an age-appropriate privacy notice, revocation, audit logs, and a hosted backend. Never reward users for exposing private information.

## Notifications worker

- Deploy `worker/` behind HTTPS with persistent job storage before enabling it.
- Set `ROBLOX_UNIVERSE_ID`, `ROBLOX_OPEN_CLOUD_API_KEY`, `WORKER_SHARED_SECRET`, and notification string IDs in hosting secrets.
- Configure the game with the worker URL and a Roblox Secret, then replace the in-memory job store with a durable adapter.
- Preserve the worker's per-user UTC delivery ledger in that durable adapter so Roblox's one-notification-per-day limit remains enforced across restarts.
