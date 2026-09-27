# API contract

## Consumer application boundary

The reusable core creates `public.social_commands` but grants no browser role access to it. Each consumer supplies its own RLS policy and enqueue function.

Dance CRM supplies:

### `public.enqueue_social_command(...)`

`SECURITY INVOKER`.

Arguments:

- command type;
- source type;
- source UUID;
- operation;
- non-secret JSON payload;
- priority.

The caller must satisfy the command-table RLS policy. The function does not gain privileges on behalf of the caller.

Dance CRM currently accepts event commands for:

- `social.publish / announcement`;
- `social.update / updated`;
- `social.cancel / cancelled`;
- `social.rsvp_update / rsvp_update`;
- `social.unpublish / unpublished`.

### `public.admin_queue_event_social_publication(...)`

Admin convenience wrapper for the event adapter. It still enqueues a command; it does not write private publisher state.

## Public durable command table

### `public.social_commands`

This is intentionally exposed because it is the asynchronous security boundary. Authenticated users receive only the permissions required to enqueue commands, constrained by RLS. They do not receive normal read/update/delete access.

The service worker claims and updates command state.

## Service-only worker RPCs

These functions are executable only by `service_role`:

- `public.social_configure_workers(...)`;
- `public.social_get_worker_secret()`
- `public.social_claim_commands(...)`
- `public.social_process_command(...)`
- `public.social_mark_command_failure(...)`
- `public.social_get_destination(...)`
- `public.social_get_publication_context(...)`
- `public.social_claim_publication_jobs(...)`
- `public.social_mark_publish_started(...)`
- `public.social_patch_job_progress(...)`
- `public.social_mark_publication_success(...)`
- `public.social_mark_publication_failure(...)`

Some of these are `SECURITY DEFINER` by design. They are not browser authority boundaries: only the system worker/service role can execute them, and they are the controlled bridge into the non-exposed `social` schema.

The command worker calls a consumer-supplied service-only hook named `public.social_process_command(command_id, worker)`. Dance CRM implements that hook in its event adapter; the reusable command queue does not know about events or other CRM tables.

## Admin operations

Authenticated administrators can use:

- `public.admin_set_social_destination(...)`;
- `public.admin_configure_social_workers(...)`;
- `public.admin_get_social_delivery_status(...)`.

Each RPC verifies the administrator app role internally.

Safe destination settings may contain routing/display configuration. Keys that look like tokens, passwords, API keys, authorization headers, webhook URLs, or secrets are rejected.
