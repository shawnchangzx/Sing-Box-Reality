#!/bin/bash

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

print_with_delay "sing-reality-box" 0.05
echo ""

# Install base dependencies
install_base() {
  if ! command -v jq &> /dev/null; then
      echo "jq not found. Installing..."
      if command -v apt &> /dev/null; then
          apt update -y && apt install -y jq curl
      elif command -v yum &> /dev/null; then
          yum install -y epel-release && yum install -y jq curl
      elif command -v dnf &> /dev/null; then
          dnf install -y jq curl
      else
          echo "Cannot install jq. Install manually."
          exit 1
      fi
  fi
}

download_singbox(){
  mkdir -p /root/sbox
  arch=$(uname -m)
  case ${arch} in
      x86_64) arch="amd64" ;;
      aarch64) arch="arm64" ;;
      armv7l) arch="armv7" ;;
  esac
  latest_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r '.tag_name')
  pkg_name="sing-box-${latest_tag#v}-linux-${arch}"
  url="https://github.com/SagerNet/sing-box/releases/download/${latest_tag}/${pkg_name}.tar.gz"
  curl -sLo "/root/${pkg_name}.tar.gz" "$url"
  tar -xzf "/root/${pkg_name}.tar.gz" -C /root
  mv "/root/${pkg_name}/sing-box" /root/sbox/sing-box
  chmod +x /root/sbox/sing-box
  rm -rf "/root/${pkg_name}.tar.gz" "/root/${pkg_name}"
}

show_client_configuration() {
  listen_port=$(jq -r '.inbounds[0].listen_port' /root/sbox/sbconfig_server.json)
  server_name=$(jq -r '.inbounds[0].tls.server_name' /root/sbox/sbconfig_server.json)
  uuid=$(jq -r '.inbounds[0].users[0].uuid' /root/sbox/sbconfig_server.json)
  public_key=$(base64 --decode /root/sbox/public.key.b64)
  short_id=$(jq -r '.inbounds[0].tls.reality.short_id[0]' /root/sbox/sbconfig_server.json)
  server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)

  show_notice "Reality 客户端通用链接"
  echo "vless://$uuid@$server_ip:$listen_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$server_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#SING-BOX-Reality"
}

install_base
download_singbox

echo "配置 Reality 节点"
mkdir -p /root/sbox

key_pair=$(/root/sbox/sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
echo "$public_key" | base64 > /root/sbox/public.key.b64

uuid=$(/root/sbox/sing-box generate uuid)
short_id=$(/root/sbox/sing-box generate rand --hex 8)

listen_port=778
server_name="itunes.apple.com"

jq -n --arg listen_port "$listen_port" --arg server_name "$server_name" \
      --arg private_key "$private_key" --arg short_id "$short_id" --arg uuid "$uuid" '{
  "log":{"disabled":false,"level":"info","timestamp":true},
  "inbounds":[
    {"type":"vless","tag":"vless-in","listen":"::","listen_port":($listen_port|tonumber),
     "users":[{"uuid":$uuid,"flow":"xtls-rprx-vision"}],
     "tls":{"enabled":true,"server_name":$server_name,
       "reality":{"enabled":true,"handshake":{"server":$server_name,"server_port":443},
                  "private_key":$private_key,"short_id":[$short_id]}}
    }
  ],
  "outbounds":[{"type":"direct","tag":"direct"}],
  "route":{"rules":[{"protocol":"dns","action":"hijack-dns"},{"inbound":["vless-in"],"action":"direct"}],"final":"direct"}
}' > /root/sbox/sbconfig_server.json

cat >/etc/systemd/system/sing-box.service <<EOF
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

if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl start sing-box
    show_client_configuration
else
    echo "配置检查失败，请排查"
fi
