# Template renderer

## Goal

Generate deterministic social images from reusable visual templates.

The first templates are the existing Sava OpenAir designs:

- square post
- vertical Story

Background art is generated/designed once and reused. Dynamic fields such as date, time and title are rendered programmatically.

## Why not generate the whole image every time

The poster must remain deterministic:

- date must not flip from `7.6` to `6.7`;
- time must be exact;
- typography and spacing must stay consistent;
- the couple / skyline should not mutate between runs;
- square and Story variants should belong to the same visual system.

AI-generated backgrounds are source assets, not the runtime rendering engine.

## Template storage

Suggested tables:

```text
social_templates
----------------
id
key
name
format            -- square | story | landscape
width
height
engine            -- svg | imagemagick
version
background_asset_id
template_body     -- optional SVG source
settings jsonb
enabled
created_at
updated_at
```

Background images belong in Supabase Storage. Vault / secrets should only contain credentials or secret URLs, not ordinary image assets.

## Named placeholders

SVG templates should expose named fields such as:

```xml
<text id="date">{{date}}</text>
<text id="time">{{time}}</text>
<text id="title">{{title}}</text>
```

The renderer must not rely on native SVG text wrapping. SVG `<text>` does not provide the layout behavior we need.

## Text layout contract

Every dynamic text field has a bounding box and explicit layout rules.

Example:

```json
{
  "id": "title",
  "type": "text",
  "box": {
    "x": 120,
    "y": 760,
    "width": 760,
    "height": 240
  },
  "font": {
    "family": "OpenAirDisplay",
    "size": 92,
    "min_size": 58,
    "line_height": 1.02
  },
  "layout": {
    "max_lines": 2,
    "wrap": "words",
    "overflow": "shrink",
    "align": "left"
  }
}
```

Supported layout behavior should include:

- measured wrapping by real font metrics;
- max width;
- max height;
- max lines;
- word wrapping;
- hard splitting fallback for overlong tokens;
- font shrinking down to `min_size`;
- ellipsis fallback;
- line-height control;
- alignment.

The renderer first measures and lays out the text, then emits SVG `<tspan>` lines or draws equivalent text through the raster engine.

This logic should be shared between square, Story and future OG templates.

## Rendering pipeline

```text
source payload
    ↓
resolve template + version
    ↓
normalize dynamic fields
    ↓
text layout / measurement
    ↓
render SVG / compose image
    ↓
rasterize to JPEG/PNG
    ↓
Supabase Storage
    ↓
social asset row
```

Possible runtime engines:

- SVG + resvg-wasm
- SVG + ImageMagick rasterization
- ImageMagick composition directly

The existing RSLive Story renderer is a useful reference for:

- font loading;
- measured text layout;
- image validation;
- Supabase Storage upload;
- deterministic storage paths;
- renderer versioning.

## Assets

Suggested table:

```text
social_assets
-------------
id
source_type
source_id
template_id
template_version
format
storage_path
public_url
input_hash
width
height
metadata jsonb
created_at
```

## Idempotency

The generated asset should be keyed by a stable input fingerprint.

Example input:

```text
sha256(
  template_key
  + template_version
  + source_type
  + source_id
  + title
  + event_start
  + location
  + styles
  + background_asset_version
)
```

If the hash already exists, return the existing asset.

If the event time changes, the input hash changes and a new asset is generated. Old scheduled draft jobs referencing outdated content can then be cancelled or regenerated explicitly.

## Initial template set

```text
sava-openair-square:v1
sava-openair-story:v1
```

Later examples:

```text
wcs-class-square:v1
wcs-class-story:v1
hustle-class-square:v1
hustle-class-story:v1
```

## Initial dynamic fields

For Sava OpenAir:

- `date`
- `time`
- `title`
- optional `styles`
- optional `location`

Default location label:

`SAVA PROMENADE | GALLERY WALK`

Timezone for event rendering:

`Europe/Belgrade`
