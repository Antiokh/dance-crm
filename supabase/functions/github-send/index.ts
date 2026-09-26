import { Octokit } from '@octokit'
import { optionalEnv, requireEnv } from '../_shared/env.ts'

type FunctionPublishPayload = {
  schema: string
  function_name: string
  overloads: Array<{
    language: string
    args: string
    return_type: string
    source_code: string
  }>
}

type TablePublishPayload = {
  schema: string
  tables: Array<{
    table_name: string
    ddl: string
  }>
}

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

function normalizeExportSql(input: string) {
  return input.replace(/\r\n/g, '\n').replace(/\\n/g, '\n').trim()
}

function buildFunctionContent(payload: FunctionPublishPayload) {
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

    return overloadHeader + normalizeExportSql(String(overload.source_code ?? ''))
  })

  return `${header}${blocks.join('\n\n')}\n`
}

function buildTableContent(payload: TablePublishPayload) {
  const header =
    `-- AUTO-GENERATED. DO NOT EDIT.\n` +
    `-- Source: live Supabase table DDL versioning\n` +
    `-- Schema:   ${payload.schema}\n` +
    `-- Entity:   tables\n` +
    `-- Mode:     table_bundle\n` +
    `-- Updated:  ${new Date().toISOString()}\n\n`

  const blocks = payload.tables.map((table) => {
    return `-- table: ${table.table_name}\n\n${normalizeExportSql(table.ddl)}`
  })

  return `${header}${blocks.join('\n\n')}\n`
}

async function callPayloadRpc(
  rpcName: string,
  rpcBody: Record<string, unknown>,
): Promise<unknown> {
  const supabaseUrl = requireEnv('SUPABASE_URL').replace(/\/$/, '')
  const key = secretKey()

  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/${rpcName}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: key,
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify(rpcBody),
    },
  )

  const body = await response.text()
  if (!response.ok) {
    throw new Error(
      `${rpcName} RPC failed (${response.status}): ${body.slice(0, 500)}`,
    )
  }

  return JSON.parse(body)
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json({ error: 'Method not allowed' }, { status: 405 })
  }

  try {
    const body = await request.json()
    const publishToken = String(body?.publish_token ?? '')

    if (!/^[0-9a-f-]{36}$/i.test(publishToken)) {
      return Response.json({ error: 'invalid publish_token' }, { status: 400 })
    }

    const functionHistoryId = Number(body?.function_history_id)
    const tableHistoryId = Number(body?.table_history_id)
    const schemaExportId = Number(body?.schema_export_id)

    const hasFunctionId =
      Number.isSafeInteger(functionHistoryId) && functionHistoryId > 0
    const hasTableId =
      Number.isSafeInteger(tableHistoryId) && tableHistoryId > 0
    const hasSchemaExportId =
      Number.isSafeInteger(schemaExportId) && schemaExportId > 0

    const publicationKinds = [hasFunctionId, hasTableId, hasSchemaExportId]
      .filter(Boolean).length

    if (publicationKinds !== 1) {
      return Response.json(
        { error: 'provide exactly one publication id' },
        { status: 400 },
      )
    }

    let path: string
    let content: string
    let commitMessage: string
    let mode: 'function' | 'table_bundle' | 'schema_export'
    let items: number

    if (hasFunctionId) {
      const payload = await callPayloadRpc(
        'get_function_publish_payload',
        {
          p_function_history_id: functionHistoryId,
          p_publish_token: publishToken,
        },
      ) as FunctionPublishPayload

      if (
        !payload?.schema ||
        !payload?.function_name ||
        !Array.isArray(payload.overloads)
      ) {
        throw new Error('invalid function publish payload')
      }

      path = `db/${payload.schema}/${payload.function_name}.sql`
      content = buildFunctionContent(payload)
      items = payload.overloads.length
      mode = 'function'
      commitMessage =
        `[CF-Pages-Skip] sql function update: ${payload.schema}.${payload.function_name} ` +
        `(${items} overload${items === 1 ? '' : 's'})`
    } else if (hasTableId) {
      const payload = await callPayloadRpc(
        'get_table_publish_payload',
        {
          p_table_history_id: tableHistoryId,
          p_publish_token: publishToken,
        },
      ) as TablePublishPayload

      if (!payload?.schema || !Array.isArray(payload.tables)) {
        throw new Error('invalid table publish payload')
      }

      path = `db/${payload.schema}.sql`
      content = buildTableContent(payload)
      items = payload.tables.length
      mode = 'table_bundle'
      commitMessage =
        `[CF-Pages-Skip] sql tables update: ${payload.schema} ` +
        `(${items} table${items === 1 ? '' : 's'})`
    } else {
      const payload = await callPayloadRpc(
        'get_schema_export_publish_payload',
        {
          p_snapshot_id: schemaExportId,
          p_publish_token: publishToken,
        },
      ) as SchemaExportPayload

      if (
        payload?.path !== 'db/ddl.json' ||
        typeof payload.content !== 'string' ||
        typeof payload.message !== 'string'
      ) {
        throw new Error('invalid schema export publish payload')
      }

      path = payload.path
      content = payload.content
      items = 1
      mode = 'schema_export'
      commitMessage = payload.message
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
      mode,
      path,
      items,
      commit: result.data.commit.sha,
      message: commitMessage,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error('github-send failed', message)
    return Response.json({ error: message }, { status: 500 })
  }
})
