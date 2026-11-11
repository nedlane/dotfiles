# Christian's OpenCode installation

Installed 2026-11-11 for `christian` only. Official OpenCode CLI 2.2.7 is at
`/home/christian/.local/bin/opencode`, installed with:

```sh
npm install --global --prefix "$HOME/.local" @opencode/cli@2.2.7
```

Run the command as Christian. Install `christian-opencode.json` from this
directory to his `~/.config/opencode/opencode.json`, owned by Christian at
mode 0600 in a mode 0700 directory. It selects
`opencode/glm-5.3-flash-free` for main and helper requests, permits only the
signed-out OpenCode provider/integration, and contains no API credentials.
The other available models are `opencode/deepseek-v4.1-flash-free` and
`opencode/minimax-m3.1-flash-free`. Paid fallback is not configured.

Christian's T3 instance has an enabled `opencode` provider using the absolute
binary path above and these three custom model IDs. It was added through the
live settings API with a provider-instance upsert and provider refresh. Other
provider settings and the default selection were preserved. No server restart
was needed. Temporary administration sessions were revoked.

Verification returned `OPENCODE_READY` from the default free model at reported
cost 0. A request for `openai/gpt-6.1-sol` was rejected locally as unavailable.
The auth list was empty, and T3 reported OpenCode ready with three models.
The archived OpenCode sessions titled `Administrator installation check` and
`Administrator free-only policy check` are installation verification, not
Christian's work. OpenCode free-model availability can change; do not add
billing or a paid fallback when an offering disappears.
