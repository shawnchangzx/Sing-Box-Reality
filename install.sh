#!/bin/bash

# Function to print characters with delay
print_with_delay() {
    text="$1"
    delay="$2"
    for ((i = 0; i < ${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}

# Notice display function
show_notice() {
    local message="$1"
    echo "#######################################################################################################################"
    echo ""
    echo "                                ${message}"
    echo ""
    echo "#######################################################################################################################"
}

# Install jq if not exists
install_base() {
    if ! command -v jq &> /dev/null; then
        echo "jq is not installed. Installing..."
        if [ -n "$(command -v apt)" ]; then
            apt update > /dev/null 2>&1
            apt install -y jq > /dev/null 2>&1
        elif [ -n "$(command -v yum)" ]; then
            yum install -y epel-release
            yum install -y jq
        elif [ -n "$(command -v dnf)" ]; then
            dnf install -y jq
        else
            echo "Cannot install jq. Please install jq manually and rerun the script."
            exit 1
        fi
    fi
}

# Download sing-box
download_singbox() {
    arch=$(uname -m)
    case ${arch} in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
    esac
    latest_version_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | grep -Po '"tag_name": "\K.*?(?=")' | sort -V | tail -n 1)
    latest_version=${latest_version_tag#v}
    package_name="sing-box-${latest_version}-linux-${arch}"
    url="https://github.com/SagerNet/sing-box/releases/download/${latest_version_tag}/${package_name}.tar.gz"
    curl -sLo "/root/${package_name}.tar.gz" "$url"
    tar -xzf "/root/${package_name}.tar.gz" -C /root
    mv "/root/${package_name}/sing-box" /root/sbox
    rm -r "/root/${package_name}.tar.gz" "/root/${package_name}"
    chmod +x /root/sbox/sing-box
}

# Download cloudflared
download_cloudflared() {
    arch=$(uname -m)
    case ${arch} in
        x86_64) cf_arch="amd64" ;;
        aarch64) cf_arch="arm64" ;;
        armv7l) cf_arch="arm" ;;
    esac
    cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
    curl -sLo "/root/sbox/cloudflared-linux" "$cf_url"
    chmod +x /root/sbox/cloudflared-linux
}

# Regenerate cloudflared argo
regenrate_cloudflared_argo() {
    pid=$(pgrep -f cloudflared)
    [ -n "$pid" ] && kill "$pid"
    vmess_port=$(jq -r '.inbounds[0].listen_port' /root/sbox/sbconfig_server.json)
    /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux>argo.log 2>&1 &
    sleep 5
    argo=$(cat argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    echo "$argo" | base64 > /root/sbox/argo.txt.b64
    rm -rf argo.log
}

# Show Reality client configuration
show_client_configuration() {
    current_listen_port=$(jq -r '.inbounds[0].listen_port' /root/sbox/sbconfig_server.json)
    current_server_name=$(jq -r '.inbounds[0].tls.server_name' /root/sbox/sbconfig_server.json)
    uuid=$(jq -r '.inbounds[0].users[0].uuid' /root/sbox/sbconfig_server.json)
    public_key=$(base64 --decode /root/sbox/public.key.b64)
    short_id=$(jq -r '.inbounds[0].tls.reality.short_id[0]' /root/sbox/sbconfig_server.json)
    server_ip=$(curl -s4m8 ip.sb -k || curl -s6m8 ip.sb -k)
    
    show_notice "Reality 客户端通用链接"
    echo ""
    echo "vless://$uuid@$server_ip:$current_listen_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$current_server_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#SING-BOX-Reality"
    echo ""
    show_notice "Reality 客户端通用参数"
    echo ""
    echo "服务器IP: $server_ip"
    echo "端口: $current_listen_port"
    echo "UUID: $uuid"
    echo "域名SNI: $current_server_name"
    echo "Public Key: $public_key"
    echo "Short ID: $short_id"
    echo ""
}

# Uninstall sing-box
uninstall_singbox() {
    echo "Uninstalling..."
    systemctl stop sing-box
    systemctl disable sing-box > /dev/null 2>&1
    rm -f /etc/systemd/system/sing-box.service
    rm -rf /root/sbox/
    echo "DONE!"
}

# Main installation
install_base
mkdir -p "/root/sbox/"

download_singbox
download_cloudflared

echo "开始配置Reality节点"
key_pair=$(/root/sbox/sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
echo "$public_key" | base64 > /root/sbox/public.key.b64

uuid=$(/root/sbox/sing-box generate uuid)
short_id=$(/root/sbox/sing-box generate rand --hex 8)

read -p "请输入Reality端口 (默认443): " listen_port
listen_port=${listen_port:-443}
read -p "请输入域名SNI (默认itunes.apple.com): " server_name
server_name=${server_name:-itunes.apple.com}

server_ip=$(curl -s4m8 ip.sb -k || curl -s6m8 ip.sb -k)

jq -n --arg listen_port "$listen_port" --arg server_name "$server_name" --arg private_key "$private_key" --arg uuid "$uuid" --arg short_id "$short_id" '{
  "log": {"disabled": false, "level": "info", "timestamp": true},
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ($listen_port | tonumber),
      "users": [{"uuid": $uuid, "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": $server_name,
        "reality": {
          "enabled": true,
          "handshake": {"server": $server_name, "server_port": 443},
          "private_key": $private_key,
          "short_id": [$short_id]
        }
      }
    }
  ],
  "outbounds": [{"type":"direct","tag":"direct"}],
  "route": {"rules":[{"inbound":["vless-in"],"action":"direct"}],"final":"direct"}
}' > /root/sbox/sbconfig_server.json

# Create systemd service
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/root/sbox/sing-box run -c /root/sbox/sbconfig_server.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

# Start service
if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
    systemctl daemon-reload
    systemctl enable sing-box > /dev/null 2>&1
    systemctl start sing-box
    systemctl restart sing-box
    show_client_configuration
else
    echo "Error in configuration. Aborting"
fi
