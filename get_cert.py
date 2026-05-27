import ssl
import socket
import base64

hostname = 'plugins.gradle.org'
port = 443

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

with socket.create_connection((hostname, port)) as sock:
    with ctx.wrap_socket(sock, server_hostname=hostname) as ssock:
        der_cert = ssock.getpeercert(binary_form=True)
        pem_cert = b"-----BEGIN CERTIFICATE-----\n" + base64.encodebytes(der_cert) + b"-----END CERTIFICATE-----\n"
        with open('C:\\Users\\hbriceno\\Desktop\\sonero\\cert.pem', 'wb') as f:
            f.write(pem_cert)
print("Certificate saved successfully.")
