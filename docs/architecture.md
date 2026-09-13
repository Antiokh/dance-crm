# Architecture

## Scope

Dance CRM will be built in two layers:

1. A reusable social publishing subsystem.
2. The dance-school CRM domain.

The publishing subsystem is the first milestone because it is immediately useful on its own and later becomes infrastructure for event, class, course and school communications.

## Existing systems to reuse

The Supabase project `rslive.ru` already contains a mature social publishing pipeline with:

- `social_posts`
- `social_post_variants`
- `social_destinations`
- `social_publication_jobs`
- scheduling RPCs
- leased publication jobs
- retry / rate-limit state
- Instagram feed publishing
- Instagram Stories publishing
- Facebook publishing
- Threads publishing
- Telegram publishing
- Make webhook delivery

Dance CRM should reuse this architecture rather than connect to the RSLive database at runtime.

The code and schema should be ported into the DanceApp Supabase project as an independent module so that each project owns its own destinations, tokens, jobs and publication state.

## Domain boundaries

### Publishing domain

The publishing layer must not depend on a specific source type.

A post may originate from:

- `event`
- `class`
- `course`
- `announcement`
- `manual`

This prevents the social subsystem from becoming coupled to the event table.

### Dance CRM domain

The expected later domain includes:

- `dance_style`
- `class` / `course`
- `group`
- `person`
- `group_membership`
- `session`
- `attendance`
- `subscription` / `pass`
- `subscription_usage`
- `booking`
- `trainer`
- `notification`

A `group` is a cohort of people. A `session` is a concrete occurrence in time. These concepts must remain separate.

## First end-to-end flow

```text
Event/manual content created
        ↓
social source sync
        ↓
poster assets rendered
        ↓
social post + platform variants
        ↓
publication jobs scheduled
        ↓
social-publish-dispatch
        ↓
Instagram / Story / Facebook / Threads / Telegram / Make
        ↓
Telegram poll reply (when configured)
```

## OpenAir extension

OpenAir events add a weather decision layer:

```text
OpenAir event
    ↓
weather check
    ↓
good / uncertain / bad
    ↓
publication policy
```

Weather must not be embedded into the generic publisher. It belongs to event orchestration / scheduling logic.

## Deployment principle

The publisher is transport infrastructure. It should know how to deliver already-approved variants, but not how those variants were created.

The source sync / orchestration layer is responsible for:

- deciding whether publication should happen;
- producing copy;
- selecting destinations;
- rendering assets;
- scheduling jobs;
- handling event-specific follow-up such as Telegram polls.
