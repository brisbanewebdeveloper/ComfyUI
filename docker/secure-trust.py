"""Keep Conda's independent CA store consistent with the eMudhra distrust policy."""

import hashlib
import re
import ssl
from pathlib import Path

import certifi
from pip._vendor import certifi as pip_certifi

BLOCKED = {
    "d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4",
    "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b",
}
PEM = re.compile(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", re.S)


def keep_certificate(match: re.Match[str]) -> str:
    fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(match.group())).hexdigest()
    return "" if fingerprint in BLOCKED else match.group()


def secure_conda_store(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    updated = PEM.sub(keep_certificate, text)
    if updated != text:
        path.write_text(updated, encoding="utf-8")


def verify_store(name: str, context: ssl.SSLContext) -> None:
    roots = context.get_ca_certs(binary_form=True)
    if not roots or BLOCKED.intersection(hashlib.sha256(cert).hexdigest() for cert in roots):
        raise SystemExit(f"Unsafe or empty CA store: {name}")
    print(f"Verified CA store: {name}")


if __name__ == "__main__":
    paths = {Path("/opt/conda/ssl/cert.pem")}
    directory = Path("/opt/conda/ssl/certs")
    if directory.is_dir():
        paths.update(path for path in directory.iterdir() if path.is_file())
    for path in paths:
        if path.is_file():
            secure_conda_store(path)
    verify_store("default OpenSSL", ssl.create_default_context())
    for name, bundle in (("system", "/etc/ssl/certs/ca-certificates.crt"),
                         ("certifi", certifi.where()), ("pip", pip_certifi.where())):
        verify_store(name, ssl.create_default_context(cafile=bundle))
