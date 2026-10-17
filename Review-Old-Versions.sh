#!/bin/bash
# Optional migration helper; never called by installer. Default is read-only.
# Only recognizes known version-suffixed LivingPond Native apps under ~/Applications.
set -euo pipefail
APPS="$HOME/Applications"
shopt -s nullglob
candidates=("$APPS"/LivingPond\ Native\ V*.app)
valid=()
for item in "${candidates[@]}"; do
  [[ -d "$item" && ! -L "$item" ]] || continue
  name="$(basename "$item")"
  if [[ "$name" =~ ^LivingPond\ Native\ V[0-9]+\.[0-9]+(\.[0-9]+(\.[0-9]+)?)?\.app$ ]]; then
    valid+=("$item")
  fi
done
printf '一池清宁 · 旧版本检查\n'
echo '当前正式安装路径：~/Applications/一池清宁.app（此脚本永远不触碰）'
if (( ${#valid[@]} == 0 )); then echo '没有发现符合条件的历史版本。'; exit 0; fi
printf '\n发现 %s 个历史应用：\n' "${#valid[@]}"
for item in "${valid[@]}"; do printf '  %s\n' "$item"; done
if [[ "${1:-}" != "--trash" ]]; then
  printf '\n当前为只读预览，没有删除或移动任何文件。\n'
  echo '如确认历史版本无需保留，先逐个退出旧版应用，然后运行：'
  echo '/bin/bash "<本脚本路径>" --trash'
  exit 0
fi
if [[ ! -t 0 ]]; then echo '需要在交互式终端手动确认；拒绝非交互调用。' >&2; exit 2; fi
printf '\n确实要把上面这些版本全部移到废纸篓吗？\n输入 MOVE TO TRASH 才继续：'
IFS= read -r answer
if [[ "$answer" != 'MOVE TO TRASH' ]]; then echo '已取消，未做任何改动。'; exit 0; fi
TRASH="$HOME/.Trash"
[[ -d "$TRASH" ]] || { echo '废纸篓目录不存在，已停止。' >&2; exit 3; }
for item in "${valid[@]}"; do
  name="$(basename "$item" .app)"
  target="$TRASH/${name}-$(date +%Y%m%d-%H%M%S)-${RANDOM}.app"
  /bin/mv "$item" "$target"
  printf '已移到废纸篓：%s\n' "$item"
done
printf '\n清理结束。请确认旧版本已退出并检查废纸篓；没有动源码 ZIP、偏好设置或当前版本。\n'
