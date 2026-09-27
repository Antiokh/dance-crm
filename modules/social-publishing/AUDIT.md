# Social publisher reference audit

This audit records the behavior reviewed before the private-schema refactor in issue #34.

## Sources reviewed

- the current Dance CRM publisher in PR #33;
- the production social pipeline in `Antiokh/rslive.ru`;
- the simpler queued publication pattern in `Antiokh/dobri-visarun`.

No separate accessible Antiokh repository matching “Verras” was found during this audit, so no independent Verras implementation is claimed as reviewed.

## Behavior retained in Dance CRM

| Capability | Dance CRM after refactor |
| --- | --- |
| Durable application intent | `public.social_commands` |
| Private publisher state | `social.*`, not exposed through Data API |
| Separate command/delivery queues | yes |
| Telegram direct publish | yes |
| Telegram edit existing announcement | yes |
| Telegram event CTA deep links | yes |
| Threads direct publish | yes |
| Instagram feed direct publish | yes |
| Facebook via Make webhook | yes |
| Destination/shared rate gates | yes |
| Scheduling via `available_at` | yes |
| Transactional/scheduled lane model | yes |
| Expiration and dependencies | yes |
| Priority aging / anti-starvation | yes |
| Leases and retry budget | yes |
| Idempotency keys | yes |
| Fail-closed ambiguous publish handling | yes |
| Provider credentials outside database settings | yes |

The refactor changes the security/storage boundary but does not intentionally change the current event announcement rendering or provider selection.

## RSLive behavior inspected

The current RSLive production documentation and publisher source show:

- direct Telegram Bot API delivery;
- direct Threads delivery, including long-text reply chains with persisted per-part progress;
- direct Instagram feed delivery;
- a separate Instagram Stories destination;
- persisted Instagram container progress and read-only reconciliation after ambiguous `media_publish`;
- shared Instagram account rate limiting between feed and Stories;
- Make as a downstream transport rather than queue owner;
- durable queue leases, retry/backoff, idempotency and rate limiting.

Repository search of the current RSLive main branch did not identify active `sendPoll`, `message_thread_id` or `reply_to_message_id` Telegram transport code. Those items therefore were not treated as current RSLive behavior that Dance CRM had to preserve.

## Deliberate differences / follow-up parity

The current Dance CRM event consumer does **not** need or implement every RSLive editorial capability:

- Instagram Stories and Story image rendering/storage are not part of the current event announcement fan-out.
- Threads event copy is intentionally bounded and currently publishes as one post; the RSLive long-text reply-chain implementation is not copied.
- RSLive has deeper Instagram ambiguous-outcome reconciliation. Dance CRM currently records provider progress before the final publish boundary and blocks unsafe automatic retry, so it prefers a dead/manual-reconciliation outcome over a duplicate. Full read-only reconciliation is a future transport hardening item, not part of the schema-boundary refactor.
- RSLive editorial approval, canonical GitHub provenance, evergreen rotation and content-update workflows belong to RSLive's content domain and are intentionally not copied into Dance CRM.

These differences are consumer/transport capabilities, not reasons to expose publisher storage. The private `social.*` model keeps enough generic queue primitives to add those transports later without moving CRM domain state.

## Security conclusion

Provider credentials must remain server-side:

- Telegram/Threads/Instagram tokens come only from Edge Function environment secrets.
- Make webhook URLs come only from Edge Function environment secrets.
- destination settings reject token/secret/password/webhook/API-key style fields;
- the public command boundary rejects provider-secret-shaped payload keys;
- Edge workers do not access `social.*` through PostgREST table endpoints; they use service-only RPCs.

The only intentionally exposed social table is the durable command boundary. Publisher implementation state and provider responses remain in the non-exposed `social` schema.
