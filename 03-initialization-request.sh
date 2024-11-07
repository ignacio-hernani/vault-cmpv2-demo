#!/bin/bash

set -exu

openssl cmp -cmd ir \
        -newkey "${CLIENT_KEY}" \
        -subject /CN=super.example.com/ \
        -csr "${CLIENT_CSR}" \
        -certout "${CMPV2_TMPDIR}"/cmp-cert.pem \
        -server ${VAULT_ADDR} \
        -path /v1/pki_int/cmp \
        -trusted "${VAULT_CACERT}","${ROOT_CA_CERT}","${VENDOR_CA_CERT}","${MOCK_ROOT_CA_CERT}" \
        -srv_cert ${VAULT_CACERT} \
        -cert "${INITIAL_DEVICE_CERT}" \
        -own_trusted "${VENDOR_CA_CERT}","${MOCK_ROOT_CA_CERT}" \
        -key "${INITIAL_DEVICE_KEY}" \
        -extracerts "${INITIAL_DEVICE_CERT}","${VENDOR_CA_CERT}","${MOCK_ROOT_CA_CERT}" \
        -tls_used \
        -tls_cert "${INITIAL_DEVICE_CERT}" \
        -tls_key "${INITIAL_DEVICE_KEY}" \
	-tls_trusted "${VAULT_CACERT}","${VENDOR_CA_CERT}","${MOCK_ROOT_CA_CERT}" \
        -verbosity 8 \
        -reqout "${CMPV2_TMPDIR}"/ir.bin,"${CMPV2_TMPDIR}"/certconf.bin \
        -rspout "${CMPV2_TMPDIR}"/ip.bin,"${CMPV2_TMPDIR}"/pkiconf.bin \