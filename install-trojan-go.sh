#!/bin/bash

show_usage="args: [-m , -d]\
                                  [--mail=, --domain=]"
mail=""
domain=""
GETOPT_ARGS=`getopt -o m:d: -al mail:,domain: -- "$@"`
eval set -- "$GETOPT_ARGS"
while [ -n "$1" ]
do
        case "$1" in
                -m|--mail) mail=$2; shift 2;;
                -d|--domain) domain=$2; shift 2;;
                --) break ;;
                *) echo $1,$2,$show_usage; break ;;
        esac
done

if [[ -z $mail || -z $domain ]]; then
	echo "Please input your email and domain"
        echo $show_usage
        exit 0
fi

apt update && apt install -y socat unzip wget curl
curl https://get.acme.sh | sh -s email=$mail
curl -s https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest \
| grep "browser_download_url.*linux-amd64.zip" \
| cut -d : -f 2,3 \
| tr -d \" \
| wget -qi -
# wget https://github.com/p4gefau1t/trojan-go/releases/download/v0.10.6/trojan-go-linux-amd64.zip
unzip trojan-go-linux-amd64.zip -d /etc/trojan-go/
systemctl stop ufw && systemctl disable ufw

sh ~/.acme.sh/acme.sh --issue -d $domain --standalone -k ec-256

sh ~/.acme.sh/acme.sh --installcert -d $domain --fullchain-file /etc/trojan-go/trojan.crt --key-file /etc/trojan-go/trojan.key --ecc

apt install -y nginx
cat << EOF > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
        worker_connections 768;
        # multi_accept on;
}

stream {
    # 这里就是 SNI 识别，将域名映射成一个配置名 \n
    map \$ssl_preread_server_name \$backend_name {
        www.smartdeng.top web;
        $domain trojan;
    # 域名都不匹配情况下的默认值        \n
    default web;
    }

    # web，配置转发详情    \n
    upstream web {
        server 127.0.0.1:10240;
    }

    # trojan，配置转发详情    \n
    upstream trojan {
        server 127.0.0.1:10241;
    }

    # vmess，配置转发详情    \n
    upstream vmess {
        server 127.0.0.1:10242;
    }

    # 监听 443 并开启 ssl_preread
    server {
        listen 443 reuseport;
        listen [::]:443 reuseport;
        proxy_pass  \$backend_name;
        ssl_preread on;
    }
}

http {

        ##
        # Basic Settings
        ##

        sendfile on;
        tcp_nopush on;
        types_hash_max_size 2048;
        # server_tokens off;

        # server_names_hash_bucket_size 64;
        # server_name_in_redirect off;

        include /etc/nginx/mime.types;
        default_type application/octet-stream;

        ##
        # SSL Settings
        ##

        ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3; # Dropping SSLv3, ref: POODLE
        ssl_prefer_server_ciphers on;

        ##
        # Logging Settings
        ##

        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log;

        ##
        # Gzip Settings
        ##

        gzip on;

        # gzip_vary on;
        # gzip_proxied any;
        # gzip_comp_level 6;
        # gzip_buffers 16 8k;
        # gzip_http_version 1.1;
        # gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

        ##
        # Virtual Host Configs
        ##

        include /etc/nginx/conf.d/*.conf;
        include /etc/nginx/sites-enabled/*;
}
EOF

systemctl enable --now nginx && systemctl restart nginx
apt install -y uuid-runtime
uuid=$(uuidgen)

cat << EOF > /etc/trojan-go/config.json
{
  "run_type": "server",
  "local_addr": "127.0.0.1",
  "local_port": 10241,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "log_level": 1,
  "log_file": "/etc/trojan-go/test.log",
  "password": [
       "$uuid"
  ],
  "buffer_size": 32,
  "dns": [],
  "ssl": {
    "verify": true,
    "verify_hostname": true,
      "cert": "/etc/trojan-go/trojan.crt",
      "key": "/etc/trojan-go/trojan.key",
    "key_password": "",
    "cipher": "",
    "cipher_tls13": "",
    "curves": "",
    "prefer_server_cipher": false,
    "sni": "$domain",
    "alpn": [
      "http/1.1"
    ],
    "session_ticket": true,
    "reuse_session": true,
    "plain_http_response": "",
    "fingerprint": "firefox",
    "serve_plain_text": false
  },
  "tcp": {
    "no_delay": true,
    "keep_alive": true,
    "reuse_port": false,
    "prefer_ipv4": false,
    "fast_open": false,
    "fast_open_qlen": 20
  },
  "mux": {
    "enabled": true,
    "concurrency": 8,
    "idle_timeout": 60
  },
  "router": {
    "enabled": false,
    "bypass": [],
    "proxy": [],
    "block": [],
    "default_policy": "proxy",
    "domain_strategy": "as_is",
    "geoip": "/etc/trojan-go/geoip.dat",
    "geosite": "/etc/trojan-go/geosite.dat"
  },
  "websocket": {
    "enabled": true,
    "path": "/ws",
    "hostname": "$domain",
    "obfuscation_password": "",
    "double_tls": true,
    "ssl": {
      "verify": true,
      "verify_hostname": true,
      "cert": "/etc/trojan-go/trojan.crt",
      "key": "/etc/trojan-go/trojan.key",
      "key_password": "",
      "prefer_server_cipher": false,
      "sni": "$domain",
      "session_ticket": true,
      "reuse_session": true,
      "plain_http_response": ""
    }
  }
}
EOF

cat << EOF > /etc/systemd/system/trojan-go.service
[Unit]
Description=Trojan-Go - An unidentifiable mechanism that helps you bypass GFW
Documentation=https://github.com/p4gefau1t/trojan-go
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/etc/trojan-go/trojan-go -config /etc/trojan-go/config.json
Restart=on-failure
RestartSec=10
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now trojan-go

echo "Install successfully, Your password is $uuid, domain: $domain, wesocket path: /ws, login with them via trojan-go"
