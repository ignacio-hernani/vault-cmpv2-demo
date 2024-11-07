#!/bin/bash
#
# A very rough smoke test script to get a Vault CMPV2 server up and running
#

prompt() {
    echo "\n\n$1"
    #read
}

set -eux

START_VAULT="yes"

CMPV2_TMPDIR=/tmp/cmpv2-testing
CERTDIR="${CMPV2_TMPDIR}/vault-ca/"
mkdir -p "${CERTDIR}"

export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TOKEN="devroot"
export VAULT_CACERT="${CERTDIR}vault-ca.pem"
export SSL_CERT_FILE="${VAULT_CACERT}"

if [ "${START_VAULT}" == "yes" ]; then
    # Cleanup old instance
    if kill "$(pgrep 'vault')"; then
      while nc localhost 8200; do sleep 1; done
      sleep 1
    fi
    rm -f "${CMPV2_TMPDIR}/vault.log"

    vault server -dev-tls -dev-root-token-id="${VAULT_TOKEN}" -log-level=debug -dev-tls-cert-dir="${CERTDIR}" -dev-tls-san=host.docker.internal 2> "${CMPV2_TMPDIR}/vault.log" &
    while ! nc -w 1 -d localhost 8200; do sleep 1; done
fi


################################################################################
# Setup mock hardware/origin root mount and certificate
####
prompt "Setup mock hardware/origin root mount and certificate"
MOCK_ROOT_CA_CERT="${CMPV2_TMPDIR}/hardware_root_cert.pem"
vault secrets enable -path=pki_mock_origin_root -default-lease-ttl=87600 pki

vault write pki_mock_origin_root/config/urls \
      issuing_certificates="${VAULT_ADDR}/v1/pki_mock_origin_root/ca" \
      crl_distribution_points="${VAULT_ADDR}/v1/pki_mock_origin_root/crl" \
      ocsp_servers="${VAULT_ADDR}/v1/pki_mock_origin_root/ocsp"

vault write -field=certificate pki_mock_origin_root/root/generate/internal \
      common_name=fake-root-ca.com \
      ttl=87600h > "${MOCK_ROOT_CA_CERT}"

################################################################################
# Setup mock hardware/origin CA mount
####
prompt "Setup mock hardware/origin CA mount"
vault secrets enable -path=pki_mock_origin_ca -default-lease-ttl=8760 pki

vault write pki_mock_origin_ca/config/urls \
      issuing_certificates="${VAULT_ADDR}/v1/pki_mock_origin_ca/ca" \
      crl_distribution_points="${VAULT_ADDR}/v1/pki_mock_origin_ca/crl" \
      ocsp_servers="${VAULT_ADDR}/v1/pki_mock_origin_ca/ocsp"

################################################################################
# Import mock hardware/origin root mount into mock hardware/origin CA mount
####
prompt "Import mock hardware/origin root mount into mock hardware/origin CA mount"
vault write -format=json /pki_mock_origin_ca/issuers/import/cert \
      pem_bundle="@${MOCK_ROOT_CA_CERT}" \
     | jq -r '.data.imported_issuers[0]' > "${CMPV2_TMPDIR}/mock-origin-root-issuer-id.txt"

## And rename it;
MOCK_ROOT_ISSUER_ID=$(cat "${CMPV2_TMPDIR}/mock-origin-root-issuer-id.txt")

curl -X PATCH \
     -H 'Content-Type: application/merge-patch+json' \
     -H "X-Vault-Token: ${VAULT_TOKEN}" \
     -d '{"issuer_name": "root-ca"}' \
     "${VAULT_ADDR}/v1/pki_mock_origin_ca/issuer/${MOCK_ROOT_ISSUER_ID}"

vault list -detailed -format=json pki_mock_origin_ca/issuers

################################################################################
# Generate and import mock origin CA (signed by mock origin root) into mock origin mount
####
prompt "Generate and import mock origin CA (signed by mock origin root) into mock origin mount"

VENDOR_CA_CERT="${CMPV2_TMPDIR}/vendor_ca.cert.pem"
vault write -format=json pki_mock_origin_ca/intermediate/generate/internal \
     common_name="example.com Intermediate Origin Vendor Authority" \
     | jq -r '.data.csr' > "${CMPV2_TMPDIR}/pki_mock_origin_ca.csr"

vault write -format=json pki_mock_origin_root/root/sign-intermediate csr="@${CMPV2_TMPDIR}/pki_mock_origin_ca.csr" \
     ttl="43800h" \
     | jq -r '.data.certificate' > "${VENDOR_CA_CERT}"

vault write -format=json pki_mock_origin_ca/intermediate/set-signed \
     certificate="@${VENDOR_CA_CERT}" \
     | jq -r '.data.imported_issuers[0]' > "${CMPV2_TMPDIR}/mock-origin-issuer-id.txt"

MOCK_ORIGIN_ISSUER_ID=$(cat ${CMPV2_TMPDIR}/mock-origin-issuer-id.txt)

curl -X PATCH \
     -H 'Content-Type: application/merge-patch+json' \
     -H "X-Vault-Token: ${VAULT_TOKEN}" \
     -d '{"issuer_name": "mock-origin-ca"}' \
     "${VAULT_ADDR}/v1/pki_mock_origin_ca/issuer/${MOCK_ORIGIN_ISSUER_ID}"

################################################################################
# Generate a certificate for testing, issued by our mock origin CA
####
prompt "Generate a certificate for testing, issued by our mock origin CA"

INITIAL_DEVICE_CERT="${CMPV2_TMPDIR}/initial-device-cert.pem"
INITIAL_DEVICE_KEY="${CMPV2_TMPDIR}/initial-device-key.pem"
DEVICE_COMMON_NAME="device.example.com"

vault write pki_mock_origin_ca/roles/myrole allow_any_name=true ttl=121h
vault write -format=json pki_mock_origin_ca/issue/myrole common_name="${DEVICE_COMMON_NAME}" > "${CMPV2_TMPDIR}/mock-origin-client-info.json"

cat "${CMPV2_TMPDIR}/mock-origin-client-info.json" | jq -r '.data.certificate' > "${INITIAL_DEVICE_CERT}"
cat "${CMPV2_TMPDIR}/mock-origin-client-info.json" | jq -r '.data.private_key' > "${INITIAL_DEVICE_KEY}"

################################################################################
# Setup root mount
####

ROOT_CA_CERT="${CMPV2_TMPDIR}/root-ca-cert.pem"

vault secrets enable -path=pki -default-lease-ttl=8760 pki

vault write pki/config/urls \
      issuing_certificates="${VAULT_ADDR}/v1/pki/ca"
#     crl_distribution_points="${VAULT_ADDR}/v1/pki/crl" \
    #     ocsp_servers="${VAULT_ADDR}/v1/pki/ocsp"

vault write -field=certificate pki/root/generate/internal \
      common_name=root-example.com \
      ttl=8760h > "${ROOT_CA_CERT}"


################################################################################
# Setup intermediary mount
####
prompt "Setup intermediary mount"
vault secrets enable -path=pki_int -default-lease-ttl=4380 pki

vault write pki_int/config/urls \
     issuing_certificates="${VAULT_ADDR}/v1/pki_int/ca"
#     crl_distribution_points="${VAULT_ADDR}/v1/pki_int/crl" \
#     ocsp_servers="${VAULT_ADDR}/v1/pki_int/ocsp"

################################################################################
# Import root CA into intermediary mount
####
prompt "Import root CA into intermediary mount"

vault write -format=json /pki_int/issuers/import/cert \
      pem_bundle="@${ROOT_CA_CERT}" \
     | jq -r '.data.imported_issuers[0]' > "${CMPV2_TMPDIR}/root-issuer-id.txt"

ROOT_ISSUER_ID=$(cat "${CMPV2_TMPDIR}/root-issuer-id.txt")

curl -X PATCH \
     -H 'Content-Type: application/merge-patch+json' \
     -H "X-Vault-Token: ${VAULT_TOKEN}" \
     -d '{"issuer_name": "root-ca"}' \
     "${VAULT_ADDR}/v1/pki_int/issuer/${ROOT_ISSUER_ID}"

vault list -detailed -format=json pki_int/issuers

################################################################################
# Generate and import signed intermediary CA into intermediary mount
####
prompt "Generate and import signed intermediary CA into intermediary mount"

vault write -format=json pki_int/intermediate/generate/internal \
     common_name="example.com Intermediate Authority" \
     key_usage="CertSign,CRLSign,DigitalSignature" \
    | jq -r '.data.csr' > "${CMPV2_TMPDIR}/pki_intermediate.csr"

vault write -format=json pki/root/sign-intermediate csr="@${CMPV2_TMPDIR}/pki_intermediate.csr" \
      ttl="43800h" \
      use_csr_values=true \
     | jq -r '.data.certificate' > "${CMPV2_TMPDIR}/intermediate.cert.pem"

vault write -format=json pki_int/intermediate/set-signed \
     certificate=@${CMPV2_TMPDIR}/intermediate.cert.pem \
     | jq -r '.data.imported_issuers[0]' > "${CMPV2_TMPDIR}/intermediary-issuer-id.txt"

INT_ISSUER_ID=$(cat ${CMPV2_TMPDIR}/intermediary-issuer-id.txt)

curl -X PATCH \
     -H 'Content-Type: application/merge-patch+json' \
     -H "X-Vault-Token: ${VAULT_TOKEN}" \
     -d '{"issuer_name": "intermediary-ca"}' \
     "${VAULT_ADDR}/v1/pki_int/issuer/${INT_ISSUER_ID}"

################################################################################
# Setup a cert-auth mount with the mock-origin CA
###

# TODO: Docs don't require read-permissions
cat > "${CMPV2_TMPDIR}/cmpv2-policy" <<EOP
path "pki_int/cmp" {
  capabilities=["read", "update", "create"]
}
path "pki_int/roles/cmp-clients/cmp" {
  capabilities=["read", "update", "create"]
}
EOP
vault policy write access-cmp "${CMPV2_TMPDIR}/cmpv2-policy"

vault auth enable cert
vault write auth/cert/certs/cmp-vendor-ca \
    display_name="CMPV2 Vendor CA" \
    token_policies="access-cmp" \
    certificate="@${VENDOR_CA_CERT}" \
    token_type="batch" \
    allowed_common_names="${DEVICE_COMMON_NAME}"

vault write auth/cert/certs/cmp-ca \
    display_name="CMPV2 Client CA" \
    token_policies="access-cmp" \
    certificate="@${CMPV2_TMPDIR}/intermediate.cert.pem" \
    token_type="batch"

CERT_ACCESSOR=$(vault read -field=accessor sys/auth/cert)

###
# Setup a userpass mount
###
# vault auth enable userpass
# vault write auth/userpass/users/${CMPV2_USER} \
#  password=${CMPV2_PASS} \
#  token_policies="access-est" \
#  token_type="batch"

# UP_ACCESSOR=$(vault read -field=accessor sys/auth/userpass)

################################################################################
# Setup a role for est-clients
###
vault write pki_int/roles/cmp-clients \
     allowed_domains="docker.internal" \
     allow_subdomains=true \
     no_store="false" \
     max_ttl="720h" \
     use_pss="true" \
     require_cn="false"

# TODO: Fix Docs
vault write pki_int/config/cmp -<<EOC
{     
        "enabled": true,
        "default_path_policy": "sign-verbatim",
        "authenticators": {
                "cert": {                               
                        "accessor": "${CERT_ACCESSOR}"
                }
        }
}
EOC

vault secrets tune \
  -allowed-response-headers="Content-Transfer-Encoding" \
  -allowed-response-headers="Content-Length" \
  -allowed-response-headers="WWW-Authenticate" \
  -delegated-auth-accessors="${CERT_ACCESSOR}" \
  pki_int


################################################################################
# Create a CSR to be used for the CMPv2 IR request
###
prompt "Create a CSR to be used for the CMPv2 IR request"

CLIENT_CSR="${CMPV2_TMPDIR}/client-csr.pem"
CLIENT_KEY="${CMPV2_TMPDIR}/client-key.pem"

echo "\n\nGenerate a CSR + key with the following command:\n"
echo openssl req -nodes -newkey rsa:2048 -keyout "${CLIENT_KEY}" -out "${CLIENT_CSR}"

cat <<EOF
##################################################
##################################################
##################################################

To interact with the CMPV2 server set the following

export CMPV2_TMPDIR="${CMPV2_TMPDIR}"

export ROOT_CA_CERT="${ROOT_CA_CERT}"
export VAULT_ISSUER="${CMPV2_TMPDIR}/intermediate.cert.pem"
export VAULT_ADDR="${VAULT_ADDR}"
export VAULT_TOKEN="${VAULT_TOKEN}"
export VAULT_CACERT="${VAULT_CACERT}"
export SSL_CERT_FILE="${VAULT_CACERT}"

export MOCK_ROOT_CA_CERT="${MOCK_ROOT_CA_CERT}"
export VENDOR_CA_CERT="${VENDOR_CA_CERT}"
export INITIAL_DEVICE_CERT="${INITIAL_DEVICE_CERT}"
export INITIAL_DEVICE_KEY="${INITIAL_DEVICE_KEY}"
export CLIENT_CSR="${CLIENT_CSR}"
export CLIENT_KEY="${CLIENT_KEY}"
EOF