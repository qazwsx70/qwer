#!/usr/bin/env bash
# gitflow.sh —— 输入「邮箱 / 姓名 / 仓库地址」，一键完成 clone、commit、push
#
# 用法:
#   ./gitflow.sh                                   # 全弹窗（推荐）
#   ./gitflow.sh <仓库地址>                          # 地址直接给，其余弹窗
#   REPO=... NAME=... EMAIL=... MODE=4 ./gitflow.sh  # 全自动，不弹窗
#
# MODE: 1=clone  2=commit  3=push  4=全部(clone+commit+push)
#
# 弹窗实现优先级: zenity -> PowerShell 原生窗口 -> 命令行提问
# MSYS2 / UCRT64 想装 zenity:  pacman -S zenity

# ================= 弹窗工具 =================
ZENITY=""
for z in zenity "/c/Program Files/Git/usr/bin/zenity.exe"; do
  if command -v "$z" >/dev/null 2>&1 || [ -x "$z" ]; then ZENITY="$z"; break; fi
done

PS=""
for p in powershell powershell.exe "/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"; do
  if command -v "$p" >/dev/null 2>&1 || [ -x "$p" ]; then PS="$p"; break; fi
done

esc_ps() { printf "%s" "$1" | sed "s/'/''/g"; }

# 输入框: ask_input "标题" "提示" "默认值"
ask_input() {
  local title="$1" prompt="$2" default="$3" ans="" t p d
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

# 确认框: 0=是 1=否
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

need() { command -v "$1" >/dev/null 2>&1; }
need git || { echo "没找到 git，先装 Git"; exit 1; }

# ================= 1. 仓库地址 =================
echo "================ gitflow ================"
REPO="${REPO:-${1:-}}"
if [ -z "$REPO" ]; then
  REPO="$(ask_input "① 仓库地址" "仓库地址（HTTPS 或 SSH 都行）：" "https://github.com/用户名/仓库.git")"
fi
case "$REPO" in
  ""|*"用户名"*) echo "仓库地址无效，退出。"; exit 1 ;;
esac
echo "仓库地址: $REPO"

# ================= 2. 姓名 =================
DEF_NAME="$(git config user.name 2>/dev/null)"
[ -z "$DEF_NAME" ] && DEF_NAME="${USER:-user}"
NAME="${NAME:-}"
if [ -z "$NAME" ]; then
  NAME="$(ask_input "② 姓名" "git user.name（回车沿用【$DEF_NAME】）：" "$DEF_NAME")"
fi
echo "姓名: $NAME"

# ================= 3. 邮箱 =================
DEF_EMAIL="$(git config user.email 2>/dev/null)"
[ -z "$DEF_EMAIL" ] && DEF_EMAIL="你的ID+用户名@users.noreply.github.com"
EMAIL="${EMAIL:-}"
if [ -z "$EMAIL" ]; then
  EMAIL="$(ask_input "③ 邮箱" "git user.email（回车沿用【$DEF_EMAIL】）：" "$DEF_EMAIL")"
fi
case "$EMAIL" in
  ""|*"你的ID"*) echo "邮箱无效，退出。"; exit 1 ;;
esac
echo "邮箱: $EMAIL"

# ================= 4. 选操作 =================
MODE="${MODE:-}"
if [ -z "$MODE" ]; then
  MODE="$(ask_input "④ 选择操作" "1=clone  2=commit  3=push  4=全部(clone+commit+push)" "4")"
fi
case "$MODE" in
  1) DO_CLONE=1; DO_COMMIT=0; DO_PUSH=0 ;;
  2) DO_CLONE=0; DO_COMMIT=1; DO_PUSH=0 ;;
  3) DO_CLONE=0; DO_COMMIT=0; DO_PUSH=1 ;;
  4) DO_CLONE=1; DO_COMMIT=1; DO_PUSH=1 ;;
  *) echo "MODE 只能是 1/2/3/4"; exit 1 ;;
esac

# ================= 5. clone =================
if [ "$DO_CLONE" = 1 ]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "==> 当前已在 git 仓库内，跳过 clone"
  else
    DIR="$(basename "${REPO%/}" .git)"
    echo "==> 克隆到 ./$DIR"
    if git clone "$REPO"; then
      cd "$DIR" || exit 1
      echo "    已进入 $(pwd)"
    else
      echo ""
      echo "clone 失败，常见原因："
      echo "  · 网络不通 → 配代理，或 SSH 走 443（见 git-github-上手手册.md §7）"
      echo "  · 私有仓库没权限 → HTTPS 用 token，或配 SSH 密钥"
      echo "  · 目录已存在 → 换个目录，或改用 MODE=2/3 在已有仓库里操作"
      exit 1
    fi
  fi
fi

# 到这里必须在仓库内
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "当前目录不是 git 仓库。请先 MODE=1 克隆，或 cd 进项目目录再跑。"
  exit 1
fi

# ================= 6. 写身份（仓库级 local，避免污染全局）=================
echo "==> 写入身份（仅当前仓库）"
git config user.name "$NAME"
git config user.email "$EMAIL"
echo "    $NAME <$EMAIL>"

# ================= 7. 关联远端 =================
CUR_ORIGIN="$(git config --get remote.origin.url 2>/dev/null)"
if [ -z "$CUR_ORIGIN" ]; then
  git remote add origin "$REPO"
  echo "==> 已添加 origin: $REPO"
elif [ "$CUR_ORIGIN" != "$REPO" ]; then
  if ask_yesno "远端不一致" "当前 origin 是：\n$CUR_ORIGIN\n\n要改成：\n$REPO ？"; then
    git remote set-url origin "$REPO"
    echo "==> origin 已更新"
  fi
else
  echo "==> origin 已是 $REPO"
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "==> 当前分支: $BRANCH"

# ================= 8. commit =================
if [ "$DO_COMMIT" = 1 ]; then
  MSG="${MSG:-}"
  [ -z "$MSG" ] && MSG="$(ask_input "提交信息" "这次改了什么：" "update")"
  [ -z "$MSG" ] && MSG="update"
  echo "==> 提交信息: $MSG"
  if [ -z "$(git status --porcelain)" ]; then
    echo "    没有改动，跳过 commit"
  else
    git add -A
    git status --short
    git commit -m "$MSG" || { echo "commit 失败"; exit 1; }
  fi
fi

# ================= 9. push =================
if [ "$DO_PUSH" = 1 ]; then
  # 解开终端提问限制，否则会报 "terminal prompts disabled"
  unset GIT_TERMINAL_PROMPT
  export GIT_TERMINAL_PROMPT=1
  echo "==> 推送到 origin/$BRANCH"
  if git push -u origin "$BRANCH"; then
    echo ""
    echo "=========== 完成 ==========="
    echo "仓库: $REPO"
    echo "分支: $BRANCH"
    echo "身份: $NAME <$EMAIL>"
  else
    echo ""
    echo "推送失败，常见原因："
    echo "  0. 要账号密码但没处输 → HTTPS 用 token："
    echo "     git remote set-url origin https://用户名:TOKEN@github.com/用户名/仓库.git"
    echo "     （不想用 token 就配 SSH 密钥，一次生效）"
    echo "  1. 网络不通 → 配代理或 SSH over 443（见 git-github-上手手册.md §7）"
    echo "  2. GH007 私有邮箱被拒 → 换 noreply 邮箱后 git commit --amend --reset-author --no-edit"
    echo "  3. 远端有新内容 → git pull --rebase origin $BRANCH 后再推"
    exit 1
  fi
fi
