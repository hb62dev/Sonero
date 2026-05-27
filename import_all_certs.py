import ssl
import socket
import base64
import subprocess

hosts = ['repo.maven.apache.org', 'plugins.gradle.org', 'dl.google.com', 'storage.googleapis.com', 'maven.google.com']

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

for host in hosts:
    try:
        with socket.create_connection((host, 443)) as sock:
            with ctx.wrap_socket(sock, server_hostname=host) as ssock:
                der_cert = ssock.getpeercert(binary_form=True)
                pem_cert = b"-----BEGIN CERTIFICATE-----\n" + base64.encodebytes(der_cert) + b"-----END CERTIFICATE-----\n"
                cert_file = f'C:\\Users\\hbriceno\\Desktop\\sonero\\{host}.pem'
                with open(cert_file, 'wb') as f:
                    f.write(pem_cert)
                
                cmd = f'& "C:\\Program Files\\Android\\Android Studio\\jbr\\bin\\keytool.exe" -import -trustcacerts -keystore "C:\\Users\\hbriceno\\Desktop\\sonero\\mycacerts" -storepass changeit -noprompt -alias {host.replace(".", "_")} -file "{cert_file}"'
                subprocess.run(["powershell", "-Command", cmd])
                print(f"Imported {host}")
    except Exception as e:
        print(f"Failed {host}: {e}")
