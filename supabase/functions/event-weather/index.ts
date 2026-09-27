import { createCors } from '../_shared/cors.ts'
import { requireEnv } from '../_shared/env.ts'
import { supabaseFromRequest } from '../_shared/supabase.ts'

type ForecastItem = {
  dt?: number
  main?: {
    temp?: number
    feels_like?: number
    humidity?: number
  }
  weather?: Array<{
    id?: number
    main?: string
    description?: string
    icon?: string
  }>
  pop?: number
  wind?: {
    speed?: number
    deg?: number
    gust?: number
  }
  rain?: {
    '3h'?: number
  }
  snow?: {
    '3h'?: number
  }
}

type ForecastResponse = {
  cod?: string | number
  message?: string | number
  list?: ForecastItem[]
  city?: {
    name?: string
    timezone?: number
  }
}

function finiteNumber(value: unknown) {
  const number = Number(value)
  return Number.isFinite(number) ? number : null
}

function text(value: unknown) {
  return typeof value === 'string' ? value : null
}

Deno.serve(async (req) => {
  const cors = createCors(req)

  if (cors.isOptions) return cors.preflight()
  if (cors.blocked) return cors.respond()

  if (req.method !== 'POST') {
    return cors.json({ error: 'Method not allowed' }, 405)
  }

  try {
    const supabase = supabaseFromRequest(req)
    if (!supabase) {
      return cors.json({ error: 'Missing user bearer token' }, 401)
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser()

    if (authError || !user) {
      return cors.json({ error: authError?.message ?? 'Unauthorized' }, 401)
    }

    const { data: isAdmin, error: adminError } = await supabase.rpc(
      'is_current_administrator',
    )

    if (adminError) throw adminError
    if (isAdmin !== true) {
      return cors.json({ error: 'Administrator role required' }, 403)
    }

    const body = await req.json().catch(() => ({})) as Record<string, unknown>
    const latitude = finiteNumber(body.latitude)
    const longitude = finiteNumber(body.longitude)
    const startsAt = text(body.starts_at)
    const target = startsAt ? new Date(startsAt) : null

    if (
      latitude === null
      || latitude < -90
      || latitude > 90
      || longitude === null
      || longitude < -180
      || longitude > 180
      || !target
      || !Number.isFinite(target.getTime())
    ) {
      return cors.json({
        error: 'latitude, longitude and valid starts_at are required',
      }, 400)
    }

    const url = new URL('https://api.openweathermap.org/data/2.5/forecast')
    url.searchParams.set('lat', String(latitude))
    url.searchParams.set('lon', String(longitude))
    url.searchParams.set('appid', requireEnv('OPENWEATHER_API_KEY'))
    url.searchParams.set('units', 'metric')
    url.searchParams.set('lang', 'ru')

    const response = await fetch(url)
    const payload = await response.json().catch(() => ({})) as ForecastResponse

    if (!response.ok || !Array.isArray(payload.list)) {
      const providerMessage = typeof payload.message === 'string'
        ? payload.message
        : `OpenWeather HTTP ${response.status}`
      throw new Error(providerMessage)
    }

    const entries = payload.list
      .filter((item): item is ForecastItem & { dt: number } =>
        typeof item.dt === 'number' && Number.isFinite(item.dt))
      .map((item) => ({
        item,
        timestampMs: item.dt * 1000,
      }))

    if (entries.length === 0) {
      return cors.json({
        ok: true,
        available: false,
        reason: 'no_forecast_data',
      })
    }

    const targetMs = target.getTime()
    let closest = entries[0]
    for (const entry of entries.slice(1)) {
      if (
        Math.abs(entry.timestampMs - targetMs)
        < Math.abs(closest.timestampMs - targetMs)
      ) {
        closest = entry
      }
    }

    const maxDistanceMs = 3 * 60 * 60 * 1000
    if (Math.abs(closest.timestampMs - targetMs) > maxDistanceMs) {
      return cors.json({
        ok: true,
        available: false,
        reason: 'out_of_range',
        available_from: new Date(entries[0].timestampMs).toISOString(),
        available_until: new Date(entries.at(-1)!.timestampMs).toISOString(),
      })
    }

    const item = closest.item
    const condition = Array.isArray(item.weather) ? item.weather[0] : undefined

    return cors.json({
      ok: true,
      available: true,
      forecast: {
        provider: 'openweather',
        requested_at: target.toISOString(),
        forecast_at: new Date(closest.timestampMs).toISOString(),
        city_name: text(payload.city?.name),
        temperature_c: finiteNumber(item.main?.temp),
        feels_like_c: finiteNumber(item.main?.feels_like),
        humidity_pct: finiteNumber(item.main?.humidity),
        condition: text(condition?.main),
        description: text(condition?.description),
        icon: text(condition?.icon),
        precipitation_probability_pct:
          finiteNumber(item.pop) === null
            ? null
            : Math.round(Math.min(1, Math.max(0, Number(item.pop))) * 100),
        rain_3h_mm: finiteNumber(item.rain?.['3h']),
        snow_3h_mm: finiteNumber(item.snow?.['3h']),
        wind_speed_mps: finiteNumber(item.wind?.speed),
        wind_gust_mps: finiteNumber(item.wind?.gust),
        wind_direction_deg: finiteNumber(item.wind?.deg),
      },
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error('event-weather failed', message)
    return cors.json({ error: message }, 502)
  }
})
