## Demo: Vault CMPv2

**Context:**

A telco customer would like to see a demo of the new functionality of HashiCorp Vault for support of CMPv2.

**Prerequisites**
- HashiCorp Vault Enterprise 1.18.1+ent: Access to Vault Enterprise binaries and a valid license.
- OpenSSL 3.x: Required for CMP support. Ensure OpenSSL is installed with CMP enabled.
- Bash shell: The scripts are written for Bash.
- Utilities: Ensure curl, jq, and nc (netcat) are installed.

**Additional Documentation**  
https://developer.hashicorp.com/vault/docs/secrets/pki/cmpv2  
https://www.hashicorp.com/blog/vault-1-18-introduces-support-for-ipv6-and-cmpv2-while-improving-security-team-ux  

---
## Steps

**1. Export Vault Enterprise License**  
Before starting Vault, you need to export your Vault Enterprise license as an environment variable.
```
export VAULT_LICENSE="your-vault-enterprise-license-key"
```
**2. Run the Vault Setup Script**  
The first script [01-test-cmpv2.sh](01-test-cmpv2.sh), sets up Vault and configures the necessary PKI secrets engines and roles for CMPv2 testing.
```
chmod +x 01-test-cmpv2.sh && ./01-test-cmpv2.sh
```
What this script does:  
- Starts Vault in dev mode with TLS enabled: This allows for secure communication using HTTPS.  
- Sets up mock root and intermediate CAs: Simulates a hardware root CA and an origin CA.
- Generates certificates and keys: Creates the necessary certificates for testing.
- Enables and configures PKI secrets engines: Sets up PKI mounts for issuing certificates.
- Configures CMP endpoint: Enables the CMP endpoint in Vault and configures it.
- Sets up authentication methods and policies: Configures Vault authentication to use certificates.

**3. Set Environment Variables**  
After running [01-test-cmpv2.sh](01-test-cmpv2.sh) the script outputs several environment variables that need to be set for subsequent steps.  
Example output:
```
##################################################
##################################################
##################################################

To interact with the CMPV2 server set the following

export CMPV2_TMPDIR="/tmp/cmpv2-testing"

export ROOT_CA_CERT="/tmp/cmpv2-testing/root-ca-cert.pem"
export VAULT_ISSUER="/tmp/cmpv2-testing/intermediate.cert.pem"
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TOKEN="devroot"
export VAULT_CACERT="/tmp/cmpv2-testing/vault-ca/vault-ca.pem"
export SSL_CERT_FILE="/tmp/cmpv2-testing/vault-ca/vault-ca.pem"

export MOCK_ROOT_CA_CERT="/tmp/cmpv2-testing/hardware_root_cert.pem"
export VENDOR_CA_CERT="/tmp/cmpv2-testing/vendor_ca.cert.pem"
export INITIAL_DEVICE_CERT="/tmp/cmpv2-testing/initial-device-cert.pem"
export INITIAL_DEVICE_KEY="/tmp/cmpv2-testing/initial-device-key.pem"
export CLIENT_CSR="/tmp/cmpv2-testing/client-csr.pem"
export CLIENT_KEY="/tmp/cmpv2-testing/client-key.pem"
```
Copy and paste these export commands into your terminal to set them for your current session.

**4. Generate a New Private Key and CSR**  
The second script [02-new-rsa-2048-key-csr.sh](02-new-rsa-2048-key-csr.sh) generates a new RSA private key and a Certificate Signing Request (CSR). This CSR is used to request a certificate from the CMPv2 endpoint.
Now run the script:
```
openssl req -nodes -newkey rsa:2048 -keyout "${CLIENT_KEY}" -out "${CLIENT_CSR}" -subj "/CN=super.example.com"
```
What this script does:  
- Uses OpenSSL to generate a new 2048-bit RSA private key.
- Creates a CSR using the generated private key.
- The private key is saved to ${CLIENT_KEY} and the CSR to ${CLIENT_CSR}.  
Note:  
When you run the script, OpenSSL will prompt you for information to include in the CSR, such as country, state, organization, common name, etc. Fill in the details as appropriate.

**5. Run the Initialization Request Script**  
The third script [03-initialization-request.sh](03-initialization-request.sh) sends a CMPv2 Initialization Request (IR) to Vault using the CSR generated in the previous step.
```
chmod +x 03-initialization-request.sh && ./03-initialization-request.sh
```
What this script does:  
- Uses OpenSSL CMP to send an Initialization Request (IR) to the Vault CMP endpoint.
- Authenticates using the initial device certificate and key (${INITIAL_DEVICE_CERT}, ${INITIAL_DEVICE_KEY}).
- Requests a new certificate using the CSR generated earlier.
- Saves the issued certificate to ${CMPV2_TMPDIR}/cmp-cert.pem.
If you followed the steps correctly, you will see something similar at the end of the output:
```
CMP info: received PKICONF
CMP DEBUG: validating CMP message
CMP DEBUG: successfully validated signature-based CMP message protection using trust store
save_free_certs:apps/cmp.c:2272:CMP info: received 1 newly enrolled certificate(s), saving to file '/tmp/cmpv2-testing/cmp-cert.pem'
```
This indicates you the CMPv2 demo operation has been performed successfully.
