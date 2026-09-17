# Local Bannerlord speech

Native English dictation and NPC speech accompany the existing Codex text
adapter. Audio stays local. The declarative implementation is in the existing
system-manifest worktree, `modules/home/bannerlord-speech/`.

`bannerlord-speech start|stop|status` controls the on-demand user service. Login
does not start it or open the microphone. The game launcher owns a session token
and passes it to the opt-in immersion companion. The token never enters Nix
sources, logs or model requests. The service binds only to 127.0.0.1:11436.

Hold V in AI Influence's text query to dictate in English. Releasing V appends a
draft; review and edit it before submitting. Each recording is capped at 30 seconds.
The service uses PipeWire's default microphone. Closing the query cancels pending
dictation. US/Greek keyboard behavior and the actual microphone require a user
check; fixture tests cannot prove those properties.

Kokoro supplies fourteen English voices: the original eight British voices plus
American Fenrir, Michael, Onyx, Puck, Heart and Bella. The game companion owns
character casting and explicit voice overrides.
Explicit cast overrides take priority; the voice prefix selects the matching
English phonemizer, with both phonemizers sharing one CPU model. Existing Player2
voice assignments and AI memories are unchanged. Synthesis is deferred so text
does not wait for audio. The game companion owns NPC playback and cancels it when
the player advances or closes a conversation. Ambient NPC conversations and
image generation are separate systems. Late speech is discarded after conversation closure.

Both engines run on CPU with two inference threads, one inference job at a time,
and service memory thresholds of 2 GiB/3 GiB. Starting the on-demand service now
prepares the model and British frontend in a background worker before dialogue;
it does not record, generate an utterance, play audio, or hold the dictation job
lock. Health reports `speech_status` as preparing, ready or failed. A failed
preparation keeps dictation available and synthesis can retry. Preparation and
any overlapping first synthesis share a 45-second deadline per request.

The first in-game reply exposed 25.9 seconds of synthesis including lazy model
loading. A 120-character CPU fixture measured 14.7 seconds cold versus 5.6 seconds
warm. With background preparation, health was available in 0.2 seconds, model
preparation finished in 7.0 seconds, and the first requested reply took 5.4 seconds.
The complete fourteen-voice fixture peaked at 1.69 GiB with no cgroup memory
pressure or swapping. Preparing earlier removes model-loading from normal first
dialogue; speech
still needs inference time, and game/other workloads can make it slower. The
American frontend loads only on its first use, reusing the loaded weights.

The user has confirmed English dictation, NPC audio, loading the existing
campaign and creating a new save were usable; continued gameplay and voice
preference remain human checks.

Models and the English spaCy frontend are pinned and available offline. No pip
installation or runtime model downloads are needed. See the package's installed
`share/bannerlord-speech/models.json` for provenance and licences.

Verification includes HTTP behavior tests, actual mod calls through Proton,
deferred/cancelled playback contracts, actual author audio conversion with
playback intercepted, fixture transcription and local synthesis. It deliberately
does not record the microphone or play sound during unattended testing.


## Short dialogue audio and cache

`POST /v1/speech` accepts `text`, `voice`, `speed`, optional `request_id`, and
optional `format` (`wav` by default, or `ogg`). OGG responses use Vorbis directly
in the existing native encoder, avoiding a Windows WAV-to-OGG conversion.
Responses use `audio/wav` or `audio/ogg` and an `X-Speech-Cache: hit|miss` header.
The game can request an initial phrase of roughly 25–96 characters, then phrases
up to 120 characters, and begin playback while later phrases are prepared.
The worker also splits long legacy requests into parts of at most 120 characters.

The private cache lives at `~/.local/state/bannerlord-speech/audio-cache`, bounded
to 256 MiB and 2,048 entries. It stores audio under hash filenames, without a
plaintext dialogue index. Model/configuration, voice embedding, Python library
environment, text, speed and format all participate in the key. Hits avoid model
inference and survive service restarts. Corrupt entries are regenerated. Cache
creation or write failure does not disable speech; the request remains uncached.
The cache directory is 0700 and audio files are 0600.

Use a unique `request_id` for each phrase (1–80 ASCII letters, digits, hyphens or
underscores). `POST /v1/speech/cancel` with that ID responds immediately with
`{ "cancelled": true, "active": true|false }`. IDs cancelled before arrival are
rejected too, with tombstones bounded to 120 seconds and 1,024 IDs. A cancelled
request returns HTTP409 with `code: "cancelled"`; a busy uncached request returns
HTTP409 with `code: "busy"`. There is no generation queue. The companion should
retry only the current phrase while busy, and discard every stale response.
Cached audio can be returned while an obsolete inference finishes.

Cancellation is cooperative between short synthesis parts, not an immediate
abort of the current model operation. It leaves model weights loaded and stops
remaining parts. The game must stop current playback immediately itself; it
must not wait for the native cancellation acknowledgement to advance dialogue.
The existing 45-second bound remains as the failure deadline. `/health` advertises
`audio_formats`, `speech_cancel_supported` and `cache_enabled` for client checks.

Synthesized conversation audio receives up to +3 dB of gain before encoding.
A uniform per-phrase peak limit caps samples at 0.90 full scale, leaving
headroom for Vorbis encoding overshoot without clipping individual samples. This does not affect microphone input, music or battle sounds.
The cache key includes the immutable Nix runtime path, so rebuilding the engine
invalidates quieter cached audio without deleting the cache during a session.
