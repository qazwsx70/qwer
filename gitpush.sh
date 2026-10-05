#!/usr/bin/env bash
# gitpush.sh —— 弹窗版一键 add + commit + push
#
# 每次运行都会弹窗：
#   1. 填提交信息（必备）
#   2. 最后确认一次再推送
#   身份 / 远端缺失时会额外弹窗补齐（已配置则不弹）
#
# 用法:
#   ./gitpush.sh              # 全弹窗
#   ./gitpush.sh "提交信息"    # 提交信息直接给，其余仍弹窗
#
# 弹窗实现优先级: zenity(Git for Windows 自带) -> PowerShell 原生窗口 -> 命令行提问
# MSYS2 / UCRT64 想装 zenity:  pacman -S zenity

# ---------- 弹窗工具探测 ----------
ZENITY=""
for z in zenity "/c/Program Files/Git/usr/bin/zenity.exe"; do
  if command -v "$z" >/dev/null 2>&1 || [ -x "$z" ]; then ZENITY="$z"; break; fi
done

PS=""
for p in powershell powershell.exe "/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"; do
  if command -v "$p" >/dev/null 2>&1 || [ -x "$p" ]; then PS="$p"; break; fi
done

# PowerShell 单引号字符串里，' 要写成 ''
esc_ps() { printf "%s" "$1" | sed "s/'/''/g"; }

# 弹窗输入框: ask_input "标题" "提示" "默认值" -> 用户输入
ask_input() {
  local title="$1" prompt="$2" default="$3" ans=""
  local t p d
  if [ -n "$ZENITY" ]; then
    ans="$("$ZENITY" --entry --title="$title" --text="$prompt" --entry-text="$default" 2>/dev/null)"
  elif [ -n "$PS" ]; then
    t="$(esc_ps "$title")"; p="$(esc_ps "$prompt")"; d="$(esc_ps "$default")"
    ans="$("$PS" -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Add-Type -AssemblyName Microsoft.VisualBasic; [Console]::Out.Write([Microsoft.VisualBasic.Interaction]::InputBox('$p','$t','$d'))" 2>/dev/null | tr -d '\r')"
  fi
  if [ -z "$ans" ]; then
    printf "%s [%s]: " "$prompt" "$default"
    read -r ans
  fi
  [ -z "$ans" ] && ans="$default"
  echo "$ans"
}

# 弹窗确认框: ask_yesno "标题" "问题" -> 0 是 / 1 否
ask_yesno() {
  local title="$1" text="$2" r="" t x
  if [ -n "$ZENITY" ]; then
    "$ZENITY" --question --title="$title" --text="$text" 2>/dev/null && return 0 || return 1
  elif [ -n "$PS" ]; then
    t="$(esc_ps "$title")"; x="$(esc_ps "$text")"
    r="$("$PS" -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; [Console]::Out.Write([System.Windows.Forms.MessageBox]::Show('$x','$t','YesNo'))" 2>/dev/null | tr -d '\r')"
    [ "$r" = "Yes" ] && return 0 || return 1
  fi
  printf "%s (y/n): " "$text"
  read -r r
  [ "$r" = "y" ] || [ "$r" = "Y" ] && return 0 || return 1
}

# ---------- 1. 仓库 ----------
echo "==> 检查仓库"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ask_yesno "Git" "当前目录不是 git 仓库，是否执行 git init？"; then
    git init
  else
    exit 1
  fi
fi

# ---------- 2. 身份（缺才弹窗，避免 local 覆盖 global）----------
echo "==> 检查身份"
NAME="$(git config user.name || true)"
EMAIL="$(git config user.email || true)"
if [ -z "$NAME" ]; then
  NAME="$(ask_input "Git 身份" "git user.name：" "${USER:-user}")"
  git config user.name "$NAME"
fi
if [ -z "$EMAIL" ]; then
  EMAIL="$(ask_input "Git 身份" "git user.email（建议 GitHub 的 noreply 邮箱）：" "")"
  if [ -z "$EMAIL" ]; then echo "必须填邮箱"; exit 1; fi
  git config user.email "$EMAIL"
fi
echo "    $NAME <$EMAIL>"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "==> 当前分支: $BRANCH"

# ---------- 3. 远端 ----------
echo "==> 检查远端"
ORIGIN="$(git config --get remote.origin.url || true)"
if [ -z "$ORIGIN" ]; then
  ORIGIN="$(ask_input "Git 远端" "origin 仓库地址：" "https://github.com/用户名/仓库.git")"
  case "$ORIGIN" in
    ""|*"用户名"*) echo "地址无效"; exit 1 ;;
  esac
  git remote add origin "$ORIGIN"
fi
echo "    $ORIGIN"

# ---------- 4. 提交信息（每次必弹）----------
MSG="$1"
if [ -z "$MSG" ]; then
  MSG="$(ask_input "Git 提交" "提交信息（这次改了什么）：" "update")"
fi
[ -z "$MSG" ] && MSG="update"
echo "==> 提交信息: $MSG"

# ---------- 5. 最后确认（每次必弹）----------
SUMMARY="分支 $BRANCH ｜ 远端 $ORIGIN ｜ 信息：$MSG —— 确定提交并推送？"
if ! ask_yesno "确认推送" "$SUMMARY"; then
  echo "已取消。"
  exit 0
fi

# ---------- 6. 执行 ----------
echo "==> 暂存并提交"
if [ -z "$(git status --porcelain)" ]; then
  echo "    没有改动，跳过 commit"
else
  git add -A
  git status --short
  git commit -m "$MSG"
fi

echo "==> 推送到 origin/$BRANCH"
if git push -u origin "$BRANCH"; then
  echo "完成。"
else
  echo ""
  echo "推送失败，常见原因："
  echo "  1. 网络不通 -> 配代理或换 SSH over 443（见 git-github-上手手册.md §7）"
  echo "  2. GH007 私有邮箱被拒 -> 换 noreply 邮箱后 git commit --amend --reset-author --no-edit"
  echo "  3. 远端有新内容 -> git pull --rebase origin $BRANCH 后再推"
  exit 1
fi
