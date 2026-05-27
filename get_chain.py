import ssl
import socket
import OpenSSL

def get_certificate_chain(host, port=443):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    with socket.create_connection((host, port)) as sock:
        with ctx.wrap_socket(sock, server_hostname=host) as ssock:
            # We need the full chain
            cert_der = ssock.getpeercert(binary_form=True)
            # The standard ssl module doesn't easily expose the full chain without pyOpenSSL
            # Let's try to get it. Actually, if we just use pyOpenSSL...
            pass

def get_chain_pyopenssl(host, port=443):
    conn = socket.create_connection((host, port))
    ctx = OpenSSL.SSL.Context(OpenSSL.SSL.TLS_CLIENT_METHOD)
    sock = OpenSSL.SSL.Connection(ctx, conn)
    sock.set_connect_state()
    sock.set_tlsext_host_name(host.encode())
    sock.do_handshake()
    
    chain = sock.get_peer_cert_chain()
    with open("chain.pem", "w") as f:
        for cert in chain:
            pem = OpenSSL.crypto.dump_certificate(OpenSSL.crypto.FILETYPE_PEM, cert).decode('utf-8')
            f.write(pem)
    print(f"Saved {len(chain)} certs to chain.pem")
    sock.close()
    conn.close()

if __name__ == "__main__":
    get_chain_pyopenssl("dl.google.com")
