# Local Bannerlord speech

Native English dictation and NPC speech accompany the existing Codex text
adapter. Audio stays local. The declarative implementation is in the existing
system-manifest worktree, `modules/home/bannerlord-speech/`.

`bannerlord-speech start|stop|status` controls the on-demand user service. Login
does not start it or open the microphone. The game launcher owns a session token
and passes it to the opt-in immersion companion. The token never enters Nix
sources, logs or model requests. The service binds only to 127.0.0.1:11436.

Hold V in AI Influence's text query to dictate in English. Releasing V appends a
draft; review and edit it before submitting. Each recording is capped at30seconds.
The service uses PipeWire's default microphone. Closing the query cancels pending
dictation. US/Greek keyboard behavior and the actual microphone require a user
check; fixture tests cannot prove those properties.

Kokoro supplies eight English voices, with a stable cast keyed by character ID.
Explicit cast overrides take priority. Existing Player2 voice assignments and
AI memories are unchanged. AI Influence supplies audio conversion/playback and
animations; synthesis is deferred so text does not wait for audio. Ordinary
Bannerlord lines, ambient NPC conversations and image generation are outside
this feature. Late speech is discarded after conversation closure.

Both engines run on CPU with two inference threads, one inference job at a time,
and service memory thresholds of2GiB/3GiB. First speech includes model loading;
fixture measurements were8.1s cold and3.1–3.3s warm for roughly five seconds of
audio. Actual game performance remains unverified.

Models and the English spaCy frontend are pinned and available offline. No pip
installation or runtime model downloads are needed. See the package's installed
`share/bannerlord-speech/models.json` for provenance and licences.

Verification includes HTTP behavior tests, actual mod calls through Proton,
deferred/cancelled playback contracts, actual author audio conversion with
playback intercepted, fixture transcription and local synthesis. It deliberately
does not record the microphone or play sound during unattended testing.
