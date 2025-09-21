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

show_notice() {
    local message="$1"
    echo "################################################################"
    echo "                          $message                              "
    echo "################################################################"
}

print_with_delay "sing-reality-vmess-box" 0.05
echo ""

# Install base dependencies
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

# Download Sing-Box
download_singbox(){
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

# Download Cloudflared
download_cloudflared(){
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

# Show client links
show_client_configuration() {
  current_listen_port=$(jq -r '.inbounds[0].listen_port' /root/sbox/sbconfig_server.json)
  current_server_name=$(jq -r '.inbounds[0].tls.server_name' /root/sbox/sbconfig_server.json)
  uuid=$(jq -r '.inbounds[0].users[0].uuid' /root/sbox/sbconfig_server.json)
  public_key=$(base64 --decode /root/sbox/public.key.b64)
  short_id=$(jq -r '.inbounds[0].tls.reality.short_id[0]' /root/sbox/sbconfig_server.json)
  server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)

  show_notice "Reality 客户端通用链接"
  echo "vless://$uuid@$server_ip:$current_listen_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$current_server_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#SING-BOX-Reality"

  # vmess
  argo=$(base64 --decode /root/sbox/argo.txt.b64)
  vmess_uuid=$(jq -r '.inbounds[1].users[0].uuid' /root/sbox/sbconfig_server.json)
  ws_path=$(jq -r '.inbounds[1].transport.path' /root/sbox/sbconfig_server.json)
  show_notice "VMess 客户端通用链接"
  echo 'vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"sing-box-vmess-tls","tls":"tls","type":"none","v":"2"}' | base64 -w 0)
}

# Start installation
install_base
mkdir -p "/root/sbox/"
download_singbox
download_cloudflared

echo "配置 Reality 节点"
key_pair=$(/root/sbox/sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
echo "$public_key" | base64 > /root/sbox/public.key.b64
uuid=$(/root/sbox/sing-box generate uuid)
short_id=$(/root/sbox/sing-box generate rand --hex 8)

read -p "请输入 Reality 端口 (默认 888): " listen_port
listen_port=${listen_port:-888}
read -p "请输入域名 SNI (默认 itunes.apple.com): " server_name
server_name=${server_name:-itunes.apple.com}

echo "配置 VMess 节点"
vmess_uuid=$(/root/sbox/sing-box generate uuid)
read -p "请输入 VMess 端口 (默认 15555): " vmess_port
vmess_port=${vmess_port:-15555}
read -p "请输入 WS 路径 (默认随机生成): " ws_path
ws_path=${ws_path:-$(/root/sbox/sing-box generate rand --hex 6)}

# 生成 Cloudflared 地址
pid=$(pgrep -f cloudflared)
if [ -n "$pid" ]; then kill "$pid"; fi
/root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux>argo.log 2>&1 &
sleep 5
argo=$(cat argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
echo "$argo" | base64 > /root/sbox/argo.txt.b64
rm -rf argo.log

server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)

# 生成配置文件
jq -n --arg listen_port "$listen_port" --arg vmess_port "$vmess_port" --arg vmess_uuid "$vmess_uuid" --arg ws_path "$ws_path" --arg server_name "$server_name" --arg private_key "$private_key" --arg short_id "$short_id" --arg uuid "$uuid" --arg server_ip "$server_ip" '{
  "log": {"disabled": false, "level": "info", "timestamp": true},
  "inbounds":[
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ($listen_port|tonumber),
      "users":[{"uuid":$uuid,"flow":"xtls-rprx-vision"}],
      "tls":{"enabled":true,"server_name":$server_name,"reality":{"enabled":true,"handshake":{"server":$server_name,"server_port":443},"private_key":$private_key,"short_id":[$short_id]}}
    },
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "::",
      "listen_port": ($vmess_port|tonumber),
      "users":[{"uuid":$vmess_uuid,"alterId":0}],
      "transport":{"type":"ws","path":$ws_path}
    }
  ],
  "outbounds":[{"type":"direct","tag":"direct"}],
  "route":{"rules":[{"protocol":"dns","action":"hijack-dns"},{"inbound":["vless-in","vmess-in"],"action":"direct"}],"final":"direct"}
}' > /root/sbox/sbconfig_server.json

# 创建 systemd 服务
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target
[Service]
User=root
WorkingDirectory=/root
ExecStart=/root/sbox/sing-box run -c /root/sbox/sbconfig_server.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF

# 启动服务
if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl start sing-box
    show_client_configuration
else
    echo "配置检查失败，请排查"
fi
