#!/usr/local/bin/bash

RED="\e[1;91m"
BLUE="\e[34m"
END="\e[0m"
blue() { echo -e "\e[34m$1\e[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
red() { echo -e "\e[1;91m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
input() { read -rp "$(red "$1")" "$2"; }

## gen dirs
DIR=$(dirname "$(readlink -f "$0")")
BIN=${DIR}/bin
if [[ ! -d "${BIN}" ]]; then
  mkdir -p "${BIN}"
fi
CONFIG=${DIR}/config
if [[ ! -d "${CONFIG}" ]]; then
  mkdir -p "${CONFIG}"
fi

## files
NODE_INFO="${CONFIG}/NODE_INFO.txt"
NODE_TMP="/tmp/NODE_INFO_TMP_$(openssl rand -hex 16)"
CONFIG_FILE="$(ls ${CONFIG} | grep config.json)"
[[ ! -z "$CONFIG_FILE" ]] && CONFIG_FILE="${CONFIG_FILE##*/}"

## gen uuid
if [ -f "$CONFIG/UUID" ]; then
  UUID=$(cat "$CONFIG/UUID")
else
  UUID=$(uuidgen)
  echo -n "$UUID" >"$CONFIG/UUID"
fi

## default global variables
PROXY_HOST="www.visa.com.sg"
PROXY_IP="$(
  ipv6="$(curl -s --max-time 1 ipv6.ip.sb)"
  [ -z "$ipv6" ] && echo "$(curl -s ipv4.ip.sb)" || echo "[$ipv6]"
)"
PROXY="$PROXY_IP"
ARGO_YN="n"
TLS=
NODE_TYPE=
[[ ! -z "$CONFIG_FILE" ]] && NODE_TYPE="$(echo $CONFIG_FILE | cut -d "_" -f1)"
declare -i IN_PORT=
declare -i PORT=
CDN_HOST=
ARGO_HOST=
ARGO_PROXY="www.visa.com.sg"
TOKEN=
if [[ -f "${CONFIG}/TOKEN" ]]; then
  TOKEN="$(cat "${CONFIG}/TOKEN")"
fi

function get_download_url() {
  #TODO: 选择架构
  local ARCH="amd64"
  if [[ "$1" == "web" ]]; then
    echo "https://github.com/ansoncloud8/am-serv00-vmess/releases/download/1.0.0/amd64-web"
  else
    echo "https://github.com/ansoncloud8/am-serv00-vmess/releases/download/1.0.0/amd64-bot"
  fi
}

function check_install() {
  if [[ -f "${BIN}/$1" ]]; then
    printf "0"
    return
  fi
  printf "1"
}

function install_bin() {
  if [[ "$(check_install "$2")" == "0" ]]; then
    yellow "$1 已经安装"
    return
  fi

  yellow "正在安装$1..."
  wget -q -O "${BIN}/$2" "$(get_download_url "$2")"
  chmod +x "${BIN}/$2"
  yellow "安装完成"
}

function install_singbox() {
  install_bin "sing-box" "web"
}

function install_cloudflared() {
  install_bin "cloudflared" "bot"
}

function check_ps() {
  pgrep -x "$1" >>/dev/null && printf "0" || printf "1"
}

function launch() {
  if [[ "$(check_install "$2")" != "0" ]]; then
    yellow "请先安装 $1"
    return
  fi
  if [[ "$(check_ps "$2")" == "0" ]]; then
    yellow "$1 正在运行"
    yellow "正在结束$1进程"
    kill_ps "$1" "$2"
  fi
  if [[ "$1" == "sing-box" ]]; then
    if [[ -z "$NODE_TYPE" ]]; then
      red "请先生成config.json配置文件，再启动$1"
      return
    fi
    nohup ${BIN}/web run -c ${CONFIG}/${NODE_TYPE}_config.json >/dev/null 2>&1 &
  else
    if [[ -z "$TOKEN" ]]; then
      red "无法启动 $1: 无法获取 TOKEN，请先启用 argo 隧道并填写 TOKEN"
      return
    fi
    nohup ${BIN}/bot tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token $TOKEN >/dev/null 2>&1 &
  fi

  if [[ "$(check_ps "$2")" != "0" ]]; then
    red "$1 启动失败，请检查$1是否正确安装在 ${BIN}，并重新选择启动或者退出"
    return
  fi
  yellow "$1 已启动"
}

function launch_singbox() {
  launch "sing-box" "web"
}

function launch_cloudflared() {
  launch "cloudflared" "bot"
}

function kill_ps() {
  if [[ "$(check_ps "$2")" == "0" ]]; then
    pkill -x "$2"
    yellow "$1 进程已结束"
  fi
}
function quit_services() {
  kill_ps "sing-box" "web"
  kill_ps "cloudflared" "bot"
}

function gen_config() {
  rm -f ${CONFIG}/*_config.json
  cat <<EOF >${CONFIG}/${NODE_TYPE}_config.json
{
  "log": {
    "disabled": true,
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "tls://8.8.8.8",
        "strategy": "ipv4_only",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "rule_set": [
          "geosite-openai"
        ],
        "server": "wireguard"
      },
      {
        "rule_set": [
          "geosite-netflix"
        ],
        "server": "wireguard"
      },
      {
        "rule_set": [
          "geosite-category-ads-all"
        ],
        "server": "block"
      }
    ],
    "final": "google",
    "strategy": "",
    "disable_cache": false,
    "disable_expire": false
  },
    "inbounds": [
    {
      "tag": "${NODE_TYPE}-ws-in",
      "type": "${NODE_TYPE}",
      "listen": "::",
      "listen_port": ${IN_PORT},
      "users": [
      {
        "uuid": "${UUID}"
      }
    ],
    "transport": {
      "type": "ws",
      "path": "/${NODE_TYPE}",
      "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    }
 ],
    "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    },
    {
      "type": "wireguard",
      "tag": "wireguard-out",
      "server": "162.159.195.142",
      "server_port": 4198,
      "local_address": [
        "172.16.0.2/32",
        "2606:4700:110:83c7:b31f:5858:b3a8:c6b1/128"
      ],
      "private_key": "mPZo+V9qlrMGCZ7+E6z2NI6NOV34PD++TpAR09PtCWI=",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": [
        26,
        21,
        228
      ]
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "ip_is_private": true,
        "outbound": "direct"
      },
      {
        "rule_set": [
          "geosite-openai"
        ],
        "outbound": "wireguard-out"
      },
      {
        "rule_set": [
          "geosite-netflix"
        ],
        "outbound": "wireguard-out"
      },
      {
        "rule_set": [
          "geosite-category-ads-all"
        ],
        "outbound": "block"
      }
    ],
    "rule_set": [
      {
        "tag": "geosite-netflix",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-netflix.srs",
        "download_detour": "direct"
      },
      {
        "tag": "geosite-openai",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/openai.srs",
        "download_detour": "direct"
      },      
      {
        "tag": "geosite-category-ads-all",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs",
        "download_detour": "direct"
      }
    ],
    "final": "direct"
   },
   "experimental": {
      "cache_file": {
      "path": "cache.db",
      "cache_id": "mycacheid",
      "store_fakeip": true
    }
  }
}
EOF
  yellow "配置文件生成完成"
}

function gen_uuid() {
  while [[ 1 ]]; do
    input "请输入UUID [$UUID]: " ID
    if [[ "$ID" =~ ^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-4[a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12} ]]; then
      UUID=$ID
      break
    elif [[ -z "$ID" ]]; then
      break
    else
      red "请输入正确的UUID !!!"
    fi
  done
}

function gen_cdn_node() {

  gen_uuid

  local CDN_YN
  while [[ 1 ]]; do
    input "是否启用cloudflare cdn [y/N]: " CDN
    if [[ "$CDN" =~ ^[ynYN]$ ]]; then
      CDN_YN="$CDN"
      break
    elif [[ -z "$CDN" ]]; then
      CDN_YN="n"
      break
    else
      red "请重新输入是否启用cloudflare cdn !!!"
      continue
    fi
  done

  if [[ "$CDN_YN" =~ ^[yY]$ ]]; then
    while [[ 1 ]]; do
      input "请输入你的CF CDN域名: " cdn_host
      if [[ -z "$cdn_host" ]]; then
        red "请重新输入你的CF CDN域名: "
        continue
      else
        CDN_HOST="$cdn_host"
        break
      fi
    done

    local ORIGIN_RULE_YN
    while [[ 1 ]]; do
      input "是否有 Origin Rules 规则 [y/N]: " rule
      if [[ -z "$rule" || "$rule" =~ ^[nN]$ ]]; then
        ORIGIN_RULE_YN="n"
        break
      elif [[ "$rule" =~ ^[yY]$ ]]; then
        ORIGIN_RULE_YN="$rule"
        break
      else
        red "请重新输入是否有 Origin Rules 规则!!!"
      fi
    done

    if [[ "$ORIGIN_RULE_YN" =~ ^[yY]$ ]]; then
      while [[ 1 ]]; do
        input "Origin Rules 规则是否启用tls [y/N]: " tls
        if [[ "$tls" =~ ^[nN]$ || -z "$tls" ]]; then
          PORT=80
          break
        elif [[ "$tls" =~ ^[yY]$ ]]; then
          TLS='tls'
          PORT=443
          break
        else
          red "请重新输入是否启用tls!!!"
        fi
      done

      PROXY="$PROXY_HOST"
      input "请输入优选IP或域名 [$PROXY]: " IP
      if [[ ! -z "$IP" ]]; then
        PROXY="$IP"
      fi
    fi
  fi

}

function gen_argo_node() {

  gen_uuid

  local argo_host
  while [[ 1 ]]; do
    input "请输入你的 argo 隧道域名: " argo_host
    if [[ -z "$argo_host" ]]; then
      red "请重新输入你的 argo 隧道域名!!!"
      continue
    else
      ARGO_HOST="$argo_host"
      break
    fi
  done

  local token
  local token_yn
  while [[ 1 ]]; do
    if [[ -z "$TOKEN" ]]; then
      input "请输入TOKEN: " token
    else
      input "请输入TOKEN [$TOKEN]: " token
    fi

    if [[ ! -z "$TOKEN" && -z "$token" ]]; then
      break
    fi

    if [[ ! -z "$token" ]]; then
      TOKEN="$token"
      printf "$token" >"${CONFIG}/TOKEN"
      break
    fi

    red "请重新输入..."
  done

  local argo_proxy
  input "是否使用默认代理IP或域名 [www.visa.com.sg]: " argo_proxy
  if [[ ! -z "$argo_proxy" ]]; then
    ARGO_PROXY="$argo_proxy"
  fi
}

function save_node_to_file() {
  mv "${NODE_TMP}" "${NODE_INFO}"
}

function gen_url() {
  local TYPE="$1"
  yellow '生成的节点如下:'
  if [[ "$TYPE" == "vless" ]]; then
    if [[ "$ARGO_YN" =~ ^[nN]$ ]]; then
      local CDN_URL="${TYPE}://${UUID}@${PROXY}:${PORT}?security=${TLS}&sni=${CDN_HOST}&fp=random&type=ws&path=/${TYPE}?ed%3D2048&host=${CDN_HOST}&encryption=none#vless1"
      echo "$CDN_URL" >"${NODE_TMP}"
    else
      ARGO_URL="${TYPE}://${UUID}@${ARGO_PROXY}:443?security=tls&sni=${ARGO_HOST}&fp=random&type=ws&path=/${TYPE}?ed%3D2048&host=${ARGO_HOST}&encryption=none#vless2"
      echo "$ARGO_URL" >"${NODE_TMP}"
    fi
  fi
  if [[ "$TYPE" == "vmess" ]]; then
    if [[ "$ARGO_YN" =~ ^[nN]$ ]]; then
      local CDN_NODE_JSON="{\"add\":\"${PROXY}\",\"aid\":\"0\",\"host\":\"${CDN_HOST}\",\"id\":\"${UUID}\",\"net\":\"ws\",\"path\":\"/${TYPE}?ed=2048\",\"port\":\"${PORT}\",\"ps\":\"PL-SERV00\",\"scy\":\"none\",\"sni\":\"${CDN_HOST}\",\"tls\":\"${TLS}\",\"type\":\"none\",\"v\":\"2\"}"
      local CDN_URL="${TYPE}://$(echo -n "${CDN_NODE_JSON}" | base64 -w0)"
      echo "$CDN_URL" >"${NODE_TMP}"
    else
      local ARGO_NODE_JSON="{\"add\":\"${PROXY}\",\"aid\":\"0\",\"host\":\"${ARGO_HOST}\",\"id\":\"${UUID}\",\"net\":\"ws\",\"path\":\"/${TYPE}?ed=2048\",\"port\":\"${PORT}\",\"ps\":\"PL-SERV00\",\"scy\":\"none\",\"sni\":\"${ARGO_HOST}\",\"tls\":\"${TLS}\",\"type\":\"none\",\"v\":\"2\"}"
      local ARGO_URL="${TYPE}://$(echo -n "${ARGO_NODE_JSON}" | base64 -w0)"
      echo "$ARGO_URL" >"${NODE_TMP}"
    fi
  fi
  cat "${NODE_TMP}"
}

function get_exist_nodes() {
  if [[ -f "${NODE_INFO}" ]]; then
    yellow "已存在如下节点信息:\n\n$(cat ${NODE_INFO})\n\n可以使用命令 'cat ${NODE_INFO}' 查看节点信息"
  else
    red "不存在节点信息"
  fi
}

function restart_services() {
  if [[ "$(check_ps "web")" == "0" ]]; then
    launch_singbox
  fi
  if [[ "$(check_ps "bot")" == "0" ]]; then
    launch_cloudflared
  fi
}

function gen_node() {
  green "1. 生成vless节点"
  green "2. 生成vmess节点"
  green "3. 清除节点信息"
  green "4. 获取已有节点"
  green "0. 返回并保存"
  local TYPE
  local port
  local ARGO
  while [[ 1 ]]; do
    input "请输入选择(0-4): " VAR
    case "$VAR" in
    1 | 2)
      ## get IN_PORT
      while [[ 1 ]]; do
        input "请输入服务器开放的TCP端口号: " port
        if [[ "$port" -ge "1" && "$port" -le "65535" ]]; then
          IN_PORT="$port"
          PORT="$port"
          break
        else
          red "请重新输入端口号!!!"
        fi
      done

      if [[ "$VAR" == "1" ]]; then
        TYPE="vless"
      else
        TYPE="vmess"
      fi

      NODE_TYPE="$TYPE"

      while [[ 1 ]]; do
        input "是否启用ARGO隧道 [y/N]: " ARGO
        if [[ -z "$ARGO" || "$ARGO" =~ ^[nN]$ ]]; then
          gen_cdn_node
          break
        elif [[ "$ARGO" =~ ^[yY]$ ]]; then
          ARGO_YN='y'
          gen_argo_node
          break
        else
          red "请重新输入..."
        fi
      done

      gen_url "$NODE_TYPE"

      PROXY="$PROXY_IP"
      ARGO_PROXY="www.visa.com.sg"
      ARGO_YN='n'
      TLS=
      CDN_HOST=
      ARGO_HOST=
      ;;
    3)
      rm -f "${NODE_INFO}"
      yellow "节点信息清除完成"
      ;;
    4)
      get_exist_nodes
      ;;
    0)
      local save_yn
      while [[ 1 ]]; do
        input "是否保存节点 [y/N]: " save_yn
        if [[ "$save_yn" =~ ^[yY]$ ]]; then
          if [[ -z "$NODE_TYPE" ]]; then
            break
          fi
          gen_config
          save_node_to_file
          restart_services
          break
        elif [[ -z "$save_yn" || "$save_yn" =~ ^[nN]$ ]]; then
          rm -f "${NODE_TMP}"
          break
        else
          red "请重新输入..."
        fi
      done

      break
      ;;
    *)
      red "请重新输入..."
      ;;
    esac
  done

}

function main_menu() {
  green "1. 安装sing-box"
  green "2. 安装cloudflared"
  green "3. 启动sing-box服务"
  green "4. 启动cloudflared服务"
  green "5. 关闭sing-box和cloudflared服务"
  green "6. 生成节点链接和config.json配置文件"
  green "0. 退出脚本"
}

function info() {
  blue "  ©️ Copyright 2024-$(date +%Y),
   ██████╗ ██████╗  ██████╗ ███████╗ ██████╗ ██████╗ ██████╗ ███████╗
  ██╔════╝██╔═══██╗██╔═══██╗██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔════╝
  ██║     ██║   ██║██║   ██║███████╗██║     ██║   ██║██║  ██║█████╗
  ██║     ██║   ██║██║   ██║╚════██║██║     ██║   ██║██║  ██║██╔══╝
  ╚██████╗╚██████╔╝╚██████╔╝███████║╚██████╗╚██████╔╝██████╔╝███████╗
  ╚═════╝ ╚═════╝  ╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝ .
  --------------------------------------------------------------------
  ${RED}GITHUB${END} https://www.github.com/cooscode
  ${BLUE}--------------------------------------------------------------------"
}

function main() {
  clear
  info
  main_menu
  while [[ 1 ]]; do
    input "请输入选择(0-6): " VAR
    case "$VAR" in
    1)
      install_singbox
      ;;
    2)
      install_cloudflared
      ;;
    3)
      launch_singbox
      ;;
    4)
      launch_cloudflared
      ;;
    5)
      quit_services
      ;;
    6)
      clear
      info
      gen_node
      clear
      info
      main_menu
      ;;
    0)
      break
      ;;
    *)
      red "请重新输入..."
      ;;
    esac
  done

  echo
  echo "Bye!!!"
}

main
