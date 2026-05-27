import os
import subprocess

def import_pems(pem_file, jks_file):
    with open(pem_file, 'r') as f:
        content = f.read()

    certs = content.split('-----END CERTIFICATE-----')
    count = 0
    for idx, cert in enumerate(certs):
        cert = cert.strip()
        if not cert:
            continue
        cert += '\n-----END CERTIFICATE-----\n'
        
        tmp_cert = f"temp_{idx}.cer"
        with open(tmp_cert, 'w') as f:
            f.write(cert)
            
        try:
            # We use the keytool from Android Studio
            keytool = r"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
            cmd = [
                keytool,
                "-importcert",
                "-noprompt",
                "-trustcacerts",
                "-alias", f"root_{os.path.basename(pem_file)}_{idx}",
                "-file", tmp_cert,
                "-keystore", jks_file,
                "-storepass", "changeit"
            ]
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            count += 1
        finally:
            try:
                if os.path.exists(tmp_cert):
                    os.remove(tmp_cert)
            except:
                pass
                
    print(f"Imported {count} certificates from {pem_file} into {jks_file}")

import shutil
# Start by copying the default cacerts to have the standard roots
cacerts_path = r"C:\Program Files\Android\Android Studio\jbr\lib\security\cacerts"
dest_jks = "mycacerts_new"
if os.path.exists(dest_jks):
    os.remove(dest_jks)
shutil.copy(cacerts_path, dest_jks)

import_pems("windows_roots.pem", dest_jks)
import_pems("windows_roots2.pem", dest_jks)
