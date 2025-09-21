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

# Notice
show_notice() {
    local message="$1"
    echo "#######################################################################################################################"
    echo "                                                                                                                       "
    echo "                                ${message}                                                                             "
    echo "                                                                                                                       "
    echo "#######################################################################################################################"
}

# Introduction animation
print_with_delay "sing-reality-ss-box" 0.05
echo ""
echo ""

# Install base
install_base(){
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
download_singbox(){
  arch=$(uname -m)
  case ${arch} in
      x86_64) arch="amd64";;
      aarch64) arch="arm64";;
      armv7l) arch="armv7";;
  esac
  latest_version_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | grep -Po '"tag_name": "\K.*?(?=")' | sort -V | tail -n 1)
  latest_version=${latest_version_tag#v}
  package_name="sing-box-${latest_version}-linux-${arch}"
  url="https://github.com/SagerNet/sing-box/releases/download/${latest_version_tag}/${package_name}.tar.gz"
  curl -sLo "/root/${package_name}.tar.gz" "$url"
  tar -xzf "/root/${package_name}.tar.gz" -C /root
  mkdir -p /root/sbox
  mv "/root/${package_name}/sing-box" /root/sbox
  rm -r "/root/${package_name}.tar.gz" "/root/${package_name}"
  chmod +x /root/sbox/sing-box
}

# Show client configuration
show_client_configuration() {
  server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)
  current_listen_port=$(jq -r '.inbounds[0].listen_port' /root/sbox/sbconfig_server.json)
  current_server_name=$(jq -r '.inbounds[0].tls.server_name' /root/sbox/sbconfig_server.json)
  uuid=$(jq -r '.inbounds[0].users[0].uuid' /root/sbox/sbconfig_server.json)
  public_key=$(base64 --decode /root/sbox/public.key.b64)
  short_id=$(jq -r '.inbounds[0].tls.reality.short_id[0]' /root/sbox/sbconfig_server.json)

  echo ""
  show_notice "Reality 客户端通用链接"
  echo "vless://$uuid@$server_ip:$current_listen_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$current_server_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#SING-BOX-Reality"

  ss_port=$(jq -r '.inbounds[1].listen_port' /root/sbox/sbconfig_server.json)
  ss_password=$(jq -r '.inbounds[1].password' /root/sbox/sbconfig_server.json)
  ss_cipher=$(jq -r '.inbounds[1].cipher' /root/sbox/sbconfig_server.json)

  echo ""
  show_notice "SS 客户端链接 (Shadowrocket格式)"
  echo "ss://$(echo -n "$ss_cipher:$ss_password@$server_ip:$ss_port" | base64 -w0)#SING-BOX-SS"
}

# Uninstall
uninstall_singbox() {
  echo "Uninstalling..."
  systemctl stop sing-box
  systemctl disable sing-box > /dev/null 2>&1
  rm -rf /root/sbox /etc/systemd/system/sing-box.service /root/self-cert
  echo "DONE!"
}

install_base
download_singbox

# Reality & SS setup
echo "开始配置Reality节点..."
read -p "请输入Reality端口 (默认443): " listen_port
listen_port=${listen_port:-443}
read -p "请输入域名SNI (默认itunes.apple.com): " server_name
server_name=${server_name:-itunes.apple.com}

echo "开始配置SS节点..."
read -p "请输入SS监听端口 (默认8388): " ss_port
ss_port=${ss_port:-8388}
read -p "请输入SS密码 (默认随机生成): " ss_password
ss_password=${ss_password:-$(/root/sbox/sing-box generate rand --hex 8)}
read -p "请输入SS加密方式 (默认aes-128-gcm): " ss_cipher
ss_cipher=${ss_cipher:-aes-128-gcm}

# Generate Reality keys
key_pair=$(/root/sbox/sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
uuid=$(/root/sbox/sing-box generate uuid)
short_id=$(/root/sbox/sing-box generate rand --hex 8)
echo "$public_key" | base64 > /root/sbox/public.key.b64

# Get server IP
server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)

# Generate sbconfig_server.json
jq -n --arg listen_port "$listen_port" \
      --arg server_name "$server_name" \
      --arg private_key "$private_key" \
      --arg short_id "$short_id" \
      --arg uuid "$uuid" \
      --arg ss_port "$ss_port" \
      --arg ss_password "$ss_password" \
      --arg ss_cipher "$ss_cipher" \
'{
  "log": {"disabled": false,"level": "info","timestamp": true},
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ($listen_port|tonumber),
      "users": [{"uuid": $uuid,"flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": $server_name,
        "reality": {
          "enabled": true,
          "handshake": {"server": $server_name,"server_port": 443},
          "private_key": $private_key,
          "short_id": [$short_id]
        }
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": ($ss_port|tonumber),
      "password": $ss_password,
      "cipher": $ss_cipher
    }
  ],
  "outbounds": [{"type": "direct","tag": "direct"}],
  "route": {"rules":[{"protocol":"dns","action":"hijack-dns"}],"final":"direct"}
}' > /root/sbox/sbconfig_server.json

# Create sing-box.service
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
    show_client_configuration
else
    echo "Error in configuration. Aborting"
fi
