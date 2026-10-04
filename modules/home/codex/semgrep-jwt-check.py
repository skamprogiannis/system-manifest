"""Check the Semgrep token verifier against the packaged PyJWT dependency."""
import asyncio
import time
from types import SimpleNamespace

import jwt
from semgrep.mcp.utilities.token_verifier import IntrospectionTokenVerifier

secret = b"semgrep-test-secret-at-least-32-bytes"
key = jwt.PyJWK.from_dict({
    "kty": "oct",
    "k": jwt.utils.base64url_encode(secret).decode(),
    "alg": "HS256",
})
verifier = IntrospectionTokenVerifier(
    "https://example.invalid/introspect",
    "https://example.invalid/jwks",
    "http://127.0.0.1:1337",
)
verifier._jwks_client = SimpleNamespace(get_signing_key_from_jwt=lambda _: key)
claims = {"client_id": "test-client", "scope": "scan", "exp": int(time.time()) + 600}

async def check():
    token = jwt.encode(claims, secret, algorithm="HS256")
    result = await verifier.verify_token(token)
    assert result is not None and result.client_id == "test-client"
    assert result.scopes == ["scan"]
    expired = jwt.encode({**claims, "exp": 1}, secret, algorithm="HS256")
    assert await verifier.verify_token(expired) is None
    invalid = jwt.encode(claims, b"different-test-secret-at-least-32-bytes", algorithm="HS256")
    assert await verifier.verify_token(invalid) is None
    print("Semgrep JWT verification: valid accepted, expired and invalid signatures rejected")

asyncio.run(check())
