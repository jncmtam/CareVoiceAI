# VNPT Speech/Eval API Notes

Sources:

- User-provided Postman collection, "Speech to Text collection".
- `/Users/jant/Desktop/API-integration.xlsx`, sheet `SmartVoice`.
- `/Users/jant/Desktop/drive-download-20260704T175747Z-3-001/Tài liệu hướng dẫn tích hợp /Speech to Text/VNPT Smart Voice_Tài liệu mô tả API STT.docx`.
- `/Users/jant/Desktop/drive-download-20260704T175747Z-3-001/Tài liệu hướng dẫn tích hợp /Speech to Text/VNPT Smart Voice_Tài liệu mô tả API Tóm tắt.docx`.
- `/Users/jant/Desktop/drive-download-20260704T175747Z-3-001/Tài liệu hướng dẫn tích hợp /Speech to Text/vnpt_asr.proto`.
- `/Users/jant/Desktop/drive-download-20260704T175747Z-3-001/Tài liệu hướng dẫn tích hợp /Text to Speech/VNPT Smart Voice_Tài liệu mô tả API TTS.docx`.
- `/Users/jant/Desktop/drive-download-20260704T175747Z-3-001/Tài liệu hướng dẫn tích hợp /Text to Speech/Text_To_Speech (General) collection.postman_collection.json`.
- `/Users/jant/Desktop/drive-download-20260704T175747Z-3-001/Tài liệu hiệu năng sản phẩm /Hiệu năng SmartVoice.xlsx`.

These endpoints are called by the backend only. The iOS app must not call VNPT
directly or store VNPT credentials.

## Shared Variables

Postman variables referenced by the collection:

- `base_url`
- `token_id`
- `token_key`
- `access_token`

Shared auth headers:

- `token-id` or `Token-id`: `{{token_id}}`
- `token-key` or `Token-key`: `{{token_key}}`
- `Authorization`: `{{access_token}}`

The collection examples imply `Authorization` may contain the full Bearer value,
for example `Bearer ${access_token}`.

## OAuth Token

Endpoint from the STT/TTS docs:

```http
POST https://api.idg.vnpt.vn/auth/oauth/token
```

The TTS document also writes the path as `/auth-service/oauth/token`; confirm
the exact deployed path with VNPT credentials.

Headers:

```http
Content-Type: application/json
```

Body fields:

| Field | Type | Notes |
| --- | --- | --- |
| `username` | string | Email login. |
| `password` | string | Password. |
| `client_id` | string | Provided by VNPT admin. |
| `grant_type` | string | Default/value: `password`. |
| `client_secret` | string | Provided by VNPT admin. |

Response fields:

- `access_token`
- `token_type`
- `refresh_token`
- `expires_in`
- `scope`

## Speech To Text: Sync

Name: `gRPC-Recognize`

Endpoint:

```http
POST {{base_url}}/stt-service/v1/grpc/standard
```

Headers:

```http
Token-id: {{token_id}}
Token-key: {{token_key}}
Authorization: {{access_token}}
```

Body: `multipart/form-data`

| Field | Type | Notes |
| --- | --- | --- |
| `audioFile` | file | Required. Audio input file; docs mention mp3, wav, pcm. Sync max file size: 10 MB. |
| `clientSession` | text | Required in docs; optional/empty in Postman sample. |
| `maxAlternatives` | integer | Optional, default `1`. |
| `audioChannelCount` | integer | Optional, default `1`. |
| `enableWordTimeOffsets` | boolean | Optional, default `false`. |
| `enableAutomaticPunctuation` | boolean | Optional, default `false`. |
| `enableSeparateRecognitionPerChannel` | boolean | Optional, default `false`. |
| `model` | string | Optional, default `offline`; docs mention current model `stream`. |
| `verbatimTranscripts` | boolean | Optional, default `false`. |
| `customConfiguration` | map | Optional. Keys include `invert_text`, `capt_punch_recovery`, `convert_format`. Use `convert_format: "mp3"` for mp3 files. |

Success response shape:

```json
{
  "message": "IDG-00000000",
  "object": {
    "results": [
      {
        "alternatives": [
          {
            "transcript": "...",
            "confidence": -1.170563
          }
        ],
        "channelTag": 1.0
      }
    ],
    "status": "OK",
    "audio_duration": 91.20001
  }
}
```

## Speech To Text: Async Long File

Name: `Async file dài`

Endpoint:

```http
POST {{base_url}}/stt-service/v1/grpc/async/standard
```

Headers:

```http
token-id: {{token_id}}
token-key: {{token_key}}
Authorization: {{access_token}}
```

Body: `multipart/form-data`

| Field | Type | Sample |
| --- | --- | --- |
| `audioFile` | file | Required for the first call only. Max file size: 250 MB or max duration: 2 hours. |
| `clientSession` | text | Required. Must be random/unique per file. Sample: `clientSession11221311209`. |
| `maxAlternatives` | integer | Optional, default `1`. |
| `audioChannelCount` | integer | Optional, default `1`. |
| `enableWordTimeOffsets` | boolean | Optional, default `false`. |
| `enableAutomaticPunctuation` | boolean | Optional, default `false`. |
| `enableSeparateRecognitionPerChannel` | boolean | Optional, default `false`. |
| `model` | string | Optional, default `offline`. |
| `verbatimTranscripts` | boolean | Optional, default `false`. |
| `customConfiguration` | map | Optional; same keys as sync STT. |

Async polling behavior:

- There is no separate polling endpoint in the provided docs.
- First call sends `audioFile` plus `clientSession`.
- If `object.status` is `ACCEPTED`, call the same endpoint again with the same
  `clientSession` and without resending `audioFile`.
- Results are cached for 10 minutes.
- Terminal success status is `OK`.

Processing response:

```json
{
  "message": "IDG-00000000",
  "object": {
    "message": "Processing",
    "status": "ACCEPTED"
  }
}
```

Success response:

```json
{
  "message": "IDG-00000000",
  "object": {
    "audio_duration": 91.20001,
    "results": [
      {
        "alternatives": [
          {
            "transcript": "...",
            "confidence": -1.6021957
          }
        ],
        "channelTag": 1
      }
    ],
    "status": "OK"
  }
}
```

## Conversation Summary

Name: `Tóm tắt dòng thời gian`

Endpoint:

```http
POST {{base_url}}/eval-emotion-service/v1/conversation/summary
```

Headers:

```http
token-id: {{token_id}}
token-key: {{token_key}}
Content-Type: application/json
Authorization: {{access_token}}
```

Body:

```json
{
  "text": "Xin chào, tôi là Trợ lý AI xử lý giọng nói",
  "languageCode": "vi-VN",
  "endMeeting": true
}
```

Request fields:

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `text` | string | Yes | Conversation content. |
| `languageCode` | string | No | `vi-VN` or `en-US`; default `vi-VN`. |
| `endMeeting` | boolean | No | Document says `True`. |

Response shape:

```json
{
  "message": "...",
  "object": {
    "summary": "..."
  }
}
```

## Meeting Summary

Name: `Tóm tắt cuộc họp`

Endpoint:

```http
POST {{base_url}}/eval-emotion-service/v1/conversation/summary-meeting
```

Headers:

```http
token-id: {{token_id}}
token-key: {{token_key}}
Content-Type: multipart/form-data
Authorization: {{access_token}}
```

Body: `multipart/form-data`

| Field | Type | Sample |
| --- | --- | --- |
| `text` | text | Empty in sample. |
| `file` | file | Optional file input. |
| `link` | text | Empty in sample. |
| `maxNumSpeakers` | text | `2` |
| `languageCode` | text | `vi-VN` |

The summary API document describes the response shape as the same summary object:

```json
{
  "message": "...",
  "object": {
    "summary": "..."
  }
}
```

The Postman collection supports summary input by `text`, `file`, or `link`.

## Text To Speech v2

Name: `Text to Speech v2 standard`

Endpoint:

```http
POST {base_url}/tts-service/v2/standard
```

Headers:

```http
Content-Type: application/json
Authorization: {{access_token}}
Token-id: {{token_id}}
Token-key: {{token_key}}
```

Body:

```json
{
  "text": "Xin chào quý khách",
  "text_split": false,
  "model": "news",
  "speed": "1",
  "region": "female_north"
}
```

Input notes from the integration workbook:

| Field | Notes |
| --- | --- |
| `text` | Required, 1-5000 characters. |
| `text_split` | Boolean. |
| `model` | Example: `news`. |
| `speed` | Example: `1`. |
| `region` | Example: `female_north` or `vi_fw_female_north`. |
| `domain` | Optional by use case. |
| `audio_format` | Optional, `wav` or `mp3`; default `wav`. |
| `sample_rate` | Optional; default `22050`; callbot can use `8000`. |
| `use_abbr_converter` | Optional, default `true`. |
| `auto_silence` | Optional, default `false`. |
| `clear_cached` | Optional. |
| `combine_final` | Optional; only useful when `text_split = true`. |
| `prosody` | Optional, valid range `[-1, 1]`, recommended `[-0.5, 0.5]`, default `0`. |

Expected output summary from the integration workbook:

- `message`
- `object.code`
- `object.playlist[]`
- `text_id`
- `version`
- `hashText`
- `lengthText`

`object.playlist[]` contains:

- `audio_link`
- `idx`
- `text`
- `text_len`
- `total`

Implementation note: audio is stored on temporary VNPT storage, so the backend
should download/copy the audio to CareVoice media storage within 24 hours if it
needs to be used for longer than the VNPT retention window.

## Text To Speech v2 gRPC HTTP Wrapper

Name: `Text to Speech cơ bản - phù hợp Callbot`

Endpoint:

```http
POST {base_url}/tts-service/v2/grpc
```

Headers are the same as TTS v2 standard.

Body example:

```json
{
  "text": "Cảm ơn anh chị đã dành thời gian lắng nghe cuộc gọi.",
  "model": "news",
  "region": "female_north",
  "speed": "1",
  "domain": "general"
}
```

The documented output shape is the same playlist/audio-link shape as TTS v2.

## Text To Speech v1 + Check Status

Endpoint:

```http
POST {base_url}/tts-service/v1/standard
```

TTS v1 returns a `text_id` and does not return the audio file immediately.
Maximum text length: 10000 characters.

Check status endpoint:

```http
POST {base_url}/tts-service/v1/check-status
```

Body:

```json
{
  "text_id": "43ae9ad3a710a5c6cf0b12d84c3be47d"
}
```

Pending response:

```json
{
  "code": "pending",
  "text_id": "7233133ba1ce49baa4a3a5d3ac946f59",
  "version": "1.0.0"
}
```

Success response returns the same `object.playlist[].audio_link` shape as TTS v2.

Error example:

```json
{
  "messageObjects": [],
  "messageFields": [],
  "statusCode": "400 BAD_REQUEST",
  "message": "IDG-00000400",
  "status": "BAD_REQUEST",
  "error": "",
  "hash_text": null,
  "length_text": null
}
```

## STT gRPC Proto

The provided proto defines:

- Service `vnpt.audio.asr.VnptSpeechRecognition`
- Unary `Recognize(RecognizeRequest) returns (RecognizeResponse)`
- Streaming `StreamingRecognize(stream StreamingRecognizeRequest) returns (stream StreamingRecognizeResponse)`

Important config fields:

- `encoding`
- `sample_rate_hertz`
- `language_code`
- `max_alternatives`
- `audio_channel_count`
- `enable_word_time_offsets`
- `enable_automatic_punctuation`
- `enable_separate_recognition_per_channel`
- `model`
- `verbatim_transcripts`
- `custom_configuration`

Audio encodings from `vnpt_audio.proto`:

- `LINEAR_PCM`
- `FLAC`
- `MULAW`
- `ALAW`

For the current FastAPI backend, the REST endpoints are simpler to integrate
than direct gRPC streaming.

## Performance And Input Notes

From the SmartVoice performance workbook:

STT:

- Input file formats: wav, mp3, m4a, ogg.
- Offline max: 250 MB, around 2 hours per conversion.
- Online stream input: PCM 16-bit, mono, 16 kHz.
- Recommended audio length for best quality: 3-10 seconds.
- Recommended recording conditions: clear speech, mic distance under 30 cm,
  low noise.
- Offline max response time: 10 seconds per 1 minute audio.
- Online response: about 400 ms per 800 ms audio chunk.

TTS:

- Backend should cache generated audio on a media server to avoid repeated TTS
  calls for the same content.
- Max response time: about 3 seconds per 400 characters.
- Throughput note: one request is 400 characters; 120 TPS in the provided
  reference setup.

## Backend Integration Mapping

The current backend mock method `VNPTGateway.transcribe_audio(...)` should call:

- Sync STT endpoint for short check-in/hotline audio.
- Async STT endpoint for longer audio if needed.

The current backend mock method `VNPTGateway.synthesize_question(...)` should
call TTS v2 standard or TTS v2 gRPC wrapper and map the first playlist item to
`audio_url`, then copy it to CareVoice media storage if it must survive beyond
the 24-hour VNPT temporary storage window.

The conversation summary endpoints can support check-in summarization/risk
analysis, but response samples are still needed before mapping fields into
CareVoice domain models.

## Remaining Details Needed For Full Implementation

- Real `base_url` for the environment we will call.
- Real credentials: username, password, client ID, client secret, token ID, token
  key.
- Confirmation whether `Authorization` env var should store raw access token or
  the full `Bearer ...` value. Docs require `Bearer ${access_token}`.
- Real sample responses from the target VNPT sandbox, especially because docs
  sometimes use camelCase and snake_case variants.
- Exact service quota/rate limits for the provided account.
