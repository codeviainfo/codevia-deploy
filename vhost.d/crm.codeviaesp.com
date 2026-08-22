# Override incluido por nginx-proxy dentro del server block de crm.codeviaesp.com.
# Redirige /api/* al backend interno; el resto sigue al frontend (generado por nginx-proxy).
location /api {
    resolver 127.0.0.11 valid=30s;
    set $crm_backend http://codevia-crm-backend:4000;
    proxy_pass $crm_backend;

    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_http_version 1.1;

    # Los jobs de scraping con Playwright pueden tardar varios minutos
    proxy_read_timeout    300s;
    proxy_connect_timeout  10s;
    proxy_send_timeout    300s;
}
