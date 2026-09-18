# Desktop local dictation

Hold `Super+Shift+T` to start an English recording and release it to transcribe
locally with Whisper. The completed transcription is copied to the Wayland
clipboard; it is not typed into the focused application. `Super+T` keeps its
existing Notes binding.

The desktop-only service starts only while the key is held and stops after the
result is copied. It writes no recording or plaintext transcription to a
persistent file or log. It refuses to start while Bannerlord or its speech
service is active, so it cannot contend with a game session.
