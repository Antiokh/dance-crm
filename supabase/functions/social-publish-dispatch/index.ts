import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type Job = {
  id: string;
  variant_id: string;
  destination_key: string;
  queue_class: "scheduled" | "transactional";
  priority: number;
  metadata: Record<string, unknown>;
};

type Variant = {
  id: string;
  platform: string;
  body: string;
  link_url: string | null;
  metadata: Record<string, unknown>;
};

type Destination = {
  key: string;
  platform: string;
  settings: Record<string, unknown>;
};

type PublishResult = {
  externalPostId?: string;
  externalPostUrl?: string;
  providerResponse?: Record<string, unknown>;
};

class PublishError extends Error {
  terminal: boolean;
  retryAfterSeconds: number;
  providerResponse: Record<string, unknown>;

  constructor(
    message: string,
    options: {
      terminal?: boolean;
      retryAfterSeconds?: number;
      providerResponse?: Record<string, unknown>;
    } = {},
  ) {
    super(message);
    this.terminal = options.terminal ?? false;
    this.retryAfterSeconds = options.retryAfterSeconds ?? 300;
    this.providerResponse = options.providerResponse ?? {};
  }
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new PublishError(`Missing secret: ${name}`, { terminal: true });
  }
  return value;
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

async function publishMake(
  variant: Variant,
  destination: Destination,
  job: Job,
): Promise<PublishResult> {
  const secretName = asString(destination.settings.webhook_secret_name) ??
    "MAKE_WEBHOOK_URL";
  const webhookUrl = requiredEnv(secretName);

  const response = await fetch(webhookUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      job_id: job.id,
      idempotency_key: job.id,
      queue_class: job.queue_class,
      priority: job.priority,
      destination: destination.key,
      platform: variant.platform,
      text: variant.body,
      link_url: variant.link_url,
      variant_metadata: variant.metadata,
      job_metadata: job.metadata,
    }),
  });

  const text = await response.text();
  if (!response.ok) {
    const retryAfter = Number(response.headers.get("retry-after") ?? "300");
    throw new PublishError(`Make webhook returned HTTP ${response.status}`, {
      terminal: response.status >= 400 && response.status < 500 && response.status !== 429,
      retryAfterSeconds: Number.isFinite(retryAfter) ? retryAfter : 300,
      providerResponse: { status: response.status, body: text.slice(0, 2000) },
    });
  }

  return {
    providerResponse: { status: response.status, body: text.slice(0, 2000) },
  };
}

async function publishTelegram(
  variant: Variant,
  destination: Destination,
  job: Job,
): Promise<PublishResult> {
  const tokenSecretName = asString(destination.settings.bot_token_secret_name) ??
    "TELEGRAM_BOT_TOKEN";
  const botToken = requiredEnv(tokenSecretName);
  const chatId = asString(destination.settings.chat_id);
  if (!chatId) {
    throw new PublishError(`Destination ${destination.key} has no chat_id`, {
      terminal: true,
    });
  }

  const method = asString(variant.metadata.telegram_method) ?? "sendMessage";
  let payload: Record<string, unknown>;

  if (method === "sendPoll") {
    const question = asString(variant.metadata.question) ?? variant.body;
    const options = Array.isArray(variant.metadata.options)
      ? variant.metadata.options.filter((item): item is string => typeof item === "string")
      : [];
    if (options.length < 2) {
      throw new PublishError("Telegram poll requires at least two options", {
        terminal: true,
      });
    }
    payload = {
      chat_id: chatId,
      question,
      options,
      is_anonymous: variant.metadata.is_anonymous ?? false,
    };
  } else if (method === "sendMessage") {
    payload = {
      chat_id: chatId,
      text: variant.body,
      disable_web_page_preview: variant.metadata.disable_web_page_preview ?? false,
    };
  } else {
    throw new PublishError(`Unsupported Telegram method: ${method}`, {
      terminal: true,
    });
  }

  const replyTo = asString(job.metadata.reply_to_message_id);
  if (replyTo) {
    payload.reply_parameters = { message_id: Number(replyTo) };
  }

  const response = await fetch(
    `https://api.telegram.org/bot${botToken}/${method}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    },
  );

  const data = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok || data.ok !== true) {
    const parameters = (data.parameters ?? {}) as Record<string, unknown>;
    const retryAfter = Number(parameters.retry_after ?? 300);
    throw new PublishError(
      asString(data.description) ?? `Telegram returned HTTP ${response.status}`,
      {
        terminal: response.status >= 400 && response.status < 500 && response.status !== 429,
        retryAfterSeconds: Number.isFinite(retryAfter) ? retryAfter : 300,
        providerResponse: data,
      },
    );
  }

  const result = (data.result ?? {}) as Record<string, unknown>;
  const messageId = result.message_id;
  return {
    externalPostId: messageId == null ? undefined : String(messageId),
    providerResponse: data,
  };
}

async function publish(
  variant: Variant,
  destination: Destination,
  job: Job,
): Promise<PublishResult> {
  switch (destination.platform) {
    case "make":
      return await publishMake(variant, destination, job);
    case "telegram":
      return await publishTelegram(variant, destination, job);
    default:
      throw new PublishError(
        `Publisher for platform '${destination.platform}' is not implemented yet`,
        { terminal: true },
      );
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const supabaseUrl = requiredEnv("SUPABASE_URL");
  const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const input = await req.json().catch(() => ({})) as Record<string, unknown>;
  const workerId = asString(input.worker_id) ?? `edge:${crypto.randomUUID()}`;
  const transactionalLimit = Number(input.transactional_limit ?? 8);
  const scheduledLimit = Number(input.scheduled_limit ?? 2);
  const leaseSeconds = Number(input.lease_seconds ?? 300);

  const { data: jobs, error: claimError } = await supabase.rpc(
    "social_claim_publication_jobs",
    {
      p_worker_id: workerId,
      p_transactional_limit: transactionalLimit,
      p_scheduled_limit: scheduledLimit,
      p_lease_seconds: leaseSeconds,
    },
  );

  if (claimError) {
    return Response.json({ ok: false, error: claimError.message }, { status: 500 });
  }

  const outcomes: Record<string, unknown>[] = [];

  for (const rawJob of (jobs ?? []) as Job[]) {
    const { data: variant, error: variantError } = await supabase
      .from("social_post_variants")
      .select("id,platform,body,link_url,metadata")
      .eq("id", rawJob.variant_id)
      .single();

    const { data: destination, error: destinationError } = await supabase
      .from("social_destinations")
      .select("key,platform,settings")
      .eq("key", rawJob.destination_key)
      .single();

    if (variantError || destinationError || !variant || !destination) {
      const errorText = variantError?.message ?? destinationError?.message ??
        "Missing variant or destination";
      await supabase.rpc("social_mark_publication_failed", {
        p_job_id: rawJob.id,
        p_worker_id: workerId,
        p_error: errorText,
        p_retry_after_seconds: 300,
        p_terminal: true,
        p_provider_response: {},
      });
      outcomes.push({ job_id: rawJob.id, ok: false, error: errorText });
      continue;
    }

    try {
      const result = await publish(
        variant as Variant,
        destination as Destination,
        rawJob,
      );
      const { error: successError } = await supabase.rpc(
        "social_mark_publication_succeeded",
        {
          p_job_id: rawJob.id,
          p_worker_id: workerId,
          p_external_post_id: result.externalPostId ?? null,
          p_external_post_url: result.externalPostUrl ?? null,
          p_provider_response: result.providerResponse ?? {},
        },
      );
      if (successError) throw successError;
      outcomes.push({ job_id: rawJob.id, ok: true });
    } catch (error) {
      const publishError = error instanceof PublishError
        ? error
        : new PublishError(error instanceof Error ? error.message : String(error));

      await supabase.rpc("social_mark_publication_failed", {
        p_job_id: rawJob.id,
        p_worker_id: workerId,
        p_error: publishError.message,
        p_retry_after_seconds: publishError.retryAfterSeconds,
        p_terminal: publishError.terminal,
        p_provider_response: publishError.providerResponse,
      });

      outcomes.push({
        job_id: rawJob.id,
        ok: false,
        terminal: publishError.terminal,
        error: publishError.message,
      });
    }
  }

  return Response.json({
    ok: true,
    worker_id: workerId,
    claimed: (jobs ?? []).length,
    outcomes,
  });
});
