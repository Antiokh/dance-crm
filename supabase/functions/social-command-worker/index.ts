import { createCors } from '../_shared/cors.ts'
import { supabaseService } from '../_shared/supabase.ts'

const WORKER_ID = 'edge:social-command-worker'
const LEASE_SECONDS = 120

type JsonRecord = Record<string, unknown>

type ClaimedCommand = {
  command_id: string
  command_type: string
  source_type: string
  source_id: string
  operation: string
  payload: JsonRecord
  attempt_count: number
  max_attempts: number
}

function errorMessage(reason: unknown) {
  return reason instanceof Error ? reason.message : String(reason)
}

function safeEqual(left: string, right: string) {
  const leftBytes = new TextEncoder().encode(left)
  const rightBytes = new TextEncoder().encode(right)
  if (leftBytes.length !== rightBytes.length) return false

  let diff = 0
  for (let index = 0; index < leftBytes.length; index += 1) {
    diff |= leftBytes[index] ^ rightBytes[index]
  }
  return diff === 0
}

async function debug(message: string, payload: unknown) {
  try {
    await supabaseService()
      .from('debug_events')
      .insert({
        source: 'social-command-worker',
        message,
        payload,
      })
  } catch {
    // Diagnostics must never break command processing.
  }
}

async function expectedSecret() {
  const { data, error } = await supabaseService()
    .rpc('social_get_dispatch_secret')

  if (error) throw error
  return typeof data === 'string' ? data : ''
}

async function claimCommands(): Promise<ClaimedCommand[]> {
  const { data, error } = await supabaseService()
    .rpc('social_claim_commands', {
      p_worker: WORKER_ID,
      p_limit: 16,
      p_lease_seconds: LEASE_SECONDS,
    })

  if (error) throw error
  return Array.isArray(data) ? data as ClaimedCommand[] : []
}

async function processCommand(command: ClaimedCommand) {
  const { data, error } = await supabaseService()
    .rpc('social_process_command', {
      p_command_id: command.command_id,
      p_worker: WORKER_ID,
    })

  if (error) throw error
  return data
}

async function markFailure(
  command: ClaimedCommand,
  reason: unknown,
  terminal = false,
) {
  const retryAfterSeconds = Math.min(
    3600,
    Math.max(30, 30 * Math.max(1, command.attempt_count)),
  )

  const { error } = await supabaseService()
    .rpc('social_mark_command_failure', {
      p_command_id: command.command_id,
      p_worker: WORKER_ID,
      p_error: errorMessage(reason),
      p_retry_after_seconds: retryAfterSeconds,
      p_terminal: terminal,
    })

  if (error) throw error
}

Deno.serve(async (request) => {
  const cors = createCors(request)

  if (cors.isOptions) return cors.preflight()
  if (cors.blocked) return cors.respond()

  if (request.method !== 'POST') {
    return cors.json({ error: 'Method not allowed' }, 405)
  }

  try {
    const provided =
      request.headers.get('x-dance-social-secret')?.trim() ?? ''
    const expected = await expectedSecret()

    if (!provided || !expected || !safeEqual(provided, expected)) {
      return cors.json({ error: 'Forbidden' }, 403)
    }

    const commands = await claimCommands()
    await debug('commands_claimed', {
      commands: commands.map((command) => ({
        command_id: command.command_id,
        command_type: command.command_type,
        source_type: command.source_type,
        source_id: command.source_id,
        operation: command.operation,
        attempt_count: command.attempt_count,
      })),
    })

    const results: JsonRecord[] = []

    for (const command of commands) {
      try {
        const result = await processCommand(command)

        await debug('command_processed', {
          command_id: command.command_id,
          source_type: command.source_type,
          source_id: command.source_id,
          operation: command.operation,
          result,
        })

        results.push({
          command_id: command.command_id,
          status: 'processed',
          result,
        })
      } catch (reason) {
        const terminal = /unsupported|invalid|not found/i.test(errorMessage(reason))

        try {
          await markFailure(command, reason, terminal)
        } catch (markReason) {
          await debug('mark_command_failure_failed', {
            command_id: command.command_id,
            original_error: errorMessage(reason),
            mark_error: errorMessage(markReason),
          })
        }

        await debug(
          terminal ? 'command_failed' : 'command_retry',
          {
            command_id: command.command_id,
            source_type: command.source_type,
            source_id: command.source_id,
            operation: command.operation,
            error: errorMessage(reason),
            terminal,
          },
        )

        results.push({
          command_id: command.command_id,
          status: terminal ? 'dead' : 'retry',
          error: errorMessage(reason),
        })
      }
    }

    return cors.json({
      ok: true,
      claimed: commands.length,
      results,
    })
  } catch (reason) {
    await debug('request_failed', {
      error: errorMessage(reason),
    })

    return cors.json({
      error: errorMessage(reason),
    }, 500)
  }
})
