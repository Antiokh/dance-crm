import { Octokit } from '@octokit'
import { optionalEnv, requireEnv } from '../_shared/env.ts'

type SchemaExportPayload = {
  path: string
  content: string
  message: string
}

function secretKey() {
  const encoded = Deno.env.get('SUPABASE_SECRET_KEYS')?.trim()
  if (encoded) {
    const parsed = JSON.parse(encoded) as Record<string, string>
    if (parsed.default) return parsed.default
  }

  return requireEnv('SUPABASE_SERVICE_ROLE_KEY')
}

function encodeUtf8Base64(input: string) {
  return btoa(unescape(encodeURIComponent(input)))
}

async function getPayload(
  snapshotId: number,
  publishToken: string,
): Promise<SchemaExportPayload> {
  const baseUrl = requireEnv('SUPABASE_URL').replace(/\/$/, '')
  const key = secretKey()

  const response = await fetch(
    `${baseUrl}/rest/v1/rpc/get_schema_export_publish_payload`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: key,
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        p_snapshot_id: snapshotId,
        p_publish_token: publishToken,
      }),
    },
  )

  const body = await response.text()
  if (!response.ok) {
    throw new Error(
      `get_schema_export_publish_payload failed (${response.status}): ${body.slice(0, 500)}`,
    )
  }

  return JSON.parse(body) as SchemaExportPayload
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json({ error: 'Method not allowed' }, { status: 405 })
  }

  try {
    const body = await request.json()
    const snapshotId = Number(body?.schema_export_id)
    const publishToken = String(body?.publish_token ?? '')

    if (!Number.isSafeInteger(snapshotId) || snapshotId <= 0) {
      return Response.json({ error: 'invalid schema_export_id' }, { status: 400 })
    }

    if (!/^[0-9a-f-]{36}$/i.test(publishToken)) {
      return Response.json({ error: 'invalid publish_token' }, { status: 400 })
    }

    const payload = await getPayload(snapshotId, publishToken)

    if (
      payload.path !== 'db/ddl.json' ||
      typeof payload.content !== 'string' ||
      typeof payload.message !== 'string'
    ) {
      throw new Error('invalid schema export payload')
    }

    const owner = optionalEnv('GITHUB_OWNER') || 'Antiokh'
    const repo = optionalEnv('GITHUB_REPO') || 'dance-crm'
    const branch = optionalEnv('GITHUB_BRANCH') || 'main'
    const octokit = new Octokit({ auth: requireEnv('GITHUB_TOKEN') })

    let sha: string | undefined
    try {
      const current = await octokit.rest.repos.getContent({
        owner,
        repo,
        path: payload.path,
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
      path: payload.path,
      message: payload.message,
      content: encodeUtf8Base64(payload.content),
      sha,
      branch,
    })

    return Response.json({
      ok: true,
      mode: 'schema_export',
      path: payload.path,
      commit: result.data.commit.sha,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error('schema-export-send failed', message)
    return Response.json({ error: message }, { status: 500 })
  }
})
