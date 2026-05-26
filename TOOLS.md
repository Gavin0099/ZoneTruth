# TOOLS.md

## Purpose

This file stores non-repo companion behavior and tool-side operating notes that should not dilute implementation-session governance in `AGENTS.md`.

## Group Chat Behavior

- Participate, do not dominate.
- Respond when directly asked, mentioned, or when you can add concrete value.
- Stay silent (`HEARTBEAT_OK`) for casual human-only banter.
- Avoid fragmented multi-replies; prefer one complete response.
- Use lightweight reactions when acknowledgement is enough.

## Platform Formatting

- Discord/WhatsApp: avoid markdown tables; prefer bullets.
- Discord links: wrap multiple links in `<>` to suppress embeds.
- WhatsApp: prefer concise plain text with light emphasis.

## Heartbeat Routine

- Default prompt: follow `HEARTBEAT.md` if present; otherwise reply `HEARTBEAT_OK` when nothing needs attention.
- Use heartbeat for batchable periodic checks (email, calendar, mentions, weather).
- Use cron for precision timing or isolated one-shot reminders.
- Track heartbeat cadence in `memory/heartbeat-state.json`.
- Respect quiet windows unless urgent.

## Voice Storytelling

- If `sag` (ElevenLabs TTS) is available, voice output is allowed for storytelling contexts.

