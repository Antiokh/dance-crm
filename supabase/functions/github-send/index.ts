import { Octokit } from '@octokit'
import { optionalEnv, requireEnv } from '../_shared/env.ts'

type PublishPayload = {
  schema: string
  function_name: string
  overloads: Array<{
    language: string
    args: string
    return_type: string
    source_code: string
  }>
}

function secretKey() {
  const encoded = Deno.env.get('SUPABASE_SECRET_KEYS')?.trim()
  if (encoded) {
    const parsed = JSON.parse(encoded) as Record<string, string>
    if (parsed.default) return parsed.default
  }

  return requireEnv('SUPABASE_SERVICE_ROLE_KEY')
}

function buildGroupedContent(payload: PublishPayload) {
  const header =
    `-- AUTO-GENERATED. DO NOT EDIT.\n` +
    `-- Source: live Supabase database function versioning\n` +
    `-- Schema:   ${payload.schema}\n` +
    `-- Function: ${payload.function_name}\n` +
    `-- Updated:  ${new Date().toISOString()}\n\n`

  const blocks = payload.overloads.map((overload) => {
    const overloadHeader =
      `-- overload\n` +
      `-- language: ${overload.language ?? ''}\n` +
      `-- args: ${overload.args ?? ''}\n` +
      `-- returns: ${overload.return_type ?? ''}\n\n`

    return overloadHeader + String(overload.source_code ?? '').trim()
  })

  return `${header}${blocks.join('\n\n')}\n`
}

function encodeUtf8Base64(input: string) {
  return btoa(unescape(encodeURIComponent(input)))
}

async function getPublishPayload(
  functionHistoryId: number,
  publishToken: string,
): Promise<PublishPayload> {
  const supabaseUrl = requireEnv('SUPABASE_URL').replace(/\/$/, '')
  const key = secretKey()

  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/get_function_publish_payload`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: key,
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        p_function_history_id: functionHistoryId,
        p_publish_token: publishToken,
      }),
    },
  )

  const body = await response.text()
  if (!response.ok) {
    throw new Error(
      `publish payload RPC failed (${response.status}): ${body.slice(0, 500)}`,
    )
  }

  return JSON.parse(body) as PublishPayload
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json({ error: 'Method not allowed' }, { status: 405 })
  }

  try {
    const body = await request.json()
    const functionHistoryId = Number(body?.function_history_id)
    const publishToken = String(body?.publish_token ?? '')

    if (!Number.isSafeInteger(functionHistoryId) || functionHistoryId <= 0) {
      return Response.json(
        { error: 'invalid function_history_id' },
        { status: 400 },
      )
    }

    if (!/^[0-9a-f-]{36}$/i.test(publishToken)) {
      return Response.json({ error: 'invalid publish_token' }, { status: 400 })
    }

    const payload = await getPublishPayload(functionHistoryId, publishToken)

    if (
      !payload?.schema ||
      !payload?.function_name ||
      !Array.isArray(payload.overloads)
    ) {
      throw new Error('invalid publish payload')
    }

    const owner = optionalEnv('GITHUB_OWNER') || 'Antiokh'
    const repo = optionalEnv('GITHUB_REPO') || 'dance-crm'
    const branch = optionalEnv('GITHUB_BRANCH') || 'main'
    const octokit = new Octokit({ auth: requireEnv('GITHUB_TOKEN') })

    const path = `db/${payload.schema}/${payload.function_name}.sql`
    const content = buildGroupedContent(payload)
    const commitMessage =
      `[CF-Pages-Skip] sql function update: ${payload.schema}.${payload.function_name} ` +
      `(${payload.overloads.length} overload${payload.overloads.length === 1 ? '' : 's'})`

    let sha: string | undefined

    try {
      const current = await octokit.rest.repos.getContent({
        owner,
        repo,
        path,
        ref: branch,
      })

      if (!Array.isArray(current.data) && current.data.type === 'file') {
        sha = current.data.sha
      }
    } catch (error) {
      const status = (error as { status?: number })?.status
      if (status !== 404) throw error
    }

    const result = await octokit.rest.repos.createOrUpdateFileContents({
      owner,
      repo,
      path,
      message: commitMessage,
      content: encodeUtf8Base64(content),
      sha,
      branch,
    })

    return Response.json({
      ok: true,
      path,
      overloads: payload.overloads.length,
      commit: result.data.commit.sha,
      message: commitMessage,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error('github-send failed', message)
    return Response.json({ error: message }, { status: 500 })
  }
})
