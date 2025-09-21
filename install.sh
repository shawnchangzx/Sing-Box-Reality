#!/bin/bash

# Sing-Box Reality 单节点安装脚本
# 只生成 Reality 节点，端口默认 778，TLS 使用苹果 CDN

echo "sing-reality-box"

# 默认端口
PORT=778

# 默认 SNI 域名
SNI="itunes.apple.com"

# 如果想让用户输入端口和SNI，可取消下面注释
# read -p "请输入 Reality 端口 (默认 778): " PORT_INPUT
# PORT=${PORT_INPUT:-778}
# read -p "请输入域名 SNI (默认 itunes.apple.com): " SNI_INPUT
# SNI=${SNI_INPUT:-itunes.apple.com}

# 生成 short_id
SHORT_ID=$(openssl rand -hex 8)

# 生成私钥和公钥
PRIVATE_KEY=$(sing-box key generate)
PUBLIC_KEY=$(sing-box key pub --private-key "$PRIVATE_KEY")

# 生成 UUID
UUID=$(uuidgen)

# 输出客户端 Reality 链接
REALITY_LINK="vless://${UUID}@$(curl -s ifconfig.me):${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#SING-BOX-Reality"

# 写入配置文件
mkdir -p /root/sbox
cat > /root/sbox/sbconfig_server.json <<EOF
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SNI}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": [
            "${SHORT_ID}"
          ]
        }
      }
    }
  ]
}
EOF

echo "################################################################"
echo "                       Reality 客户端通用链接                               "
echo "################################################################"
echo "$REALITY_LINK"

# 输出提示
echo "配置文件已生成：/root/sbox/sbconfig_server.json"
echo "请确保 sing-box 已经安装并启动服务：systemctl start sing-box"
