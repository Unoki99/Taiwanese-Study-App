#!/bin/bash
# 方方詞卡: builds the app and installs it on your iPhone / iPad and your Mac. No Xcode clicking needed.
#   bash ~/Downloads/fangfang-cards/install.sh          iPhone/iPad + Mac
#   bash ~/Downloads/fangfang-cards/install.sh ios      only iPhone/iPad
#   bash ~/Downloads/fangfang-cards/install.sh mac      only Mac
# Run it again any time (e.g. every 7 days for iPhone/iPad) to reinstall.
WHAT="${1:-all}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/FangfangCards"
DD="$HOME/Library/Developer/fangfangcards-build"
LOG="$HOME/Library/Logs/fangfangcards-build.log"
mkdir -p "$HOME/Library/Logs"

# 1. keep the project in a fixed place: ~/FangfangCards
if [ "$HERE" != "$DEST" ]; then
  mkdir -p "$DEST"
  # keep word data that was already built there
  rsync -a --delete --exclude ".DS_Store" --exclude "xcuserdata" --exclude "project.xcworkspace" \
        --exclude "FangfangCards/dict.json" --exclude "FangfangCards/cards.json" --exclude "FangfangCards/grammar.json" "$HERE/" "$DEST/"
  for f in dict.json cards.json grammar.json; do
    [ -f "$HERE/FangfangCards/$f" ] && cp "$HERE/FangfangCards/$f" "$DEST/FangfangCards/$f"
  done
fi
echo "專案：$DEST/FangfangCards.xcodeproj"

# 2. word data (built from the MOE dictionary file if it isn't there yet)
if [ ! -f "$DEST/FangfangCards/dict.json" ] || [ ! -f "$DEST/FangfangCards/cards.json" ]; then
  bash "$DEST/build-data.sh" || { echo "✗ 沒辦法建立詞典資料。"; exit 1; }
fi
# 文法 data (made from the word data; quick)
if [ ! -f "$DEST/FangfangCards/grammar.json" ]; then
  echo "整理文法資料…"
  (cd "$DEST/tools" && /usr/bin/env python3 build_grammar.py ../FangfangCards/dict.json ../FangfangCards/grammar.json > /dev/null) \
    || { echo "✗ 沒辦法建立文法資料。"; exit 1; }
fi

# 3. Apple developer team (only needed when the project doesn't have one, e.g. downloaded from GitHub)
TEAMARG=()
if grep -q 'DEVELOPMENT_TEAM = "";' "$DEST/FangfangCards.xcodeproj/project.pbxproj"; then
  TEAM="${FANGFANG_TEAM:-$(cat "$HOME/.fangfang-team" 2>/dev/null)}"
  if [ -z "$TEAM" ]; then
    TEAM=$(defaults read com.apple.dt.Xcode 2>/dev/null | grep -oE 'teamID = "?[A-Z0-9]{10}' | head -1 | grep -oE '[A-Z0-9]{10}$')
  fi
  if [ -z "$TEAM" ]; then
    echo "✗ 找不到你的 Apple 開發者團隊。請先打開 Xcode → Settings → Accounts，用 Apple ID 登入，再執行一次。"
    exit 1
  fi
  echo "$TEAM" > "$HOME/.fangfang-team"
  TEAMARG=(DEVELOPMENT_TEAM="$TEAM")
fi

fail() {
  echo "✗ 建置失敗。把下面的錯誤訊息傳給 Claude："
  grep -E "error:|error -|Signing|provision" "$LOG" | sort -u | head -25
  echo "（完整紀錄：$LOG）"
  exit 1
}

# 4. iPhone / iPad (fresh 7-day signature)
if [ "$WHAT" = "all" ] || [ "$WHAT" = "ios" ]; then
  echo "建置 iPhone／iPad 版…（第一次大概 1–2 分鐘）"
  xcodebuild -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards -configuration Debug \
     -destination "generic/platform=iOS" -derivedDataPath "$DD" -allowProvisioningUpdates "${TEAMARG[@]}" \
     build > "$LOG" 2>&1 < /dev/null || fail
  APP=$(ls -d "$DD"/Build/Products/Debug-iphoneos/*.app | head -1)
  echo "✓ 建置完成"
  JSON=$(mktemp)
  xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 < /dev/null
  IDS=$(/usr/bin/python3 - "$JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for dev in d.get("result", {}).get("devices", []):
    hw = dev.get("hardwareProperties", {}); cp = dev.get("connectionProperties", {})
    if hw.get("platform") == "iOS" and cp.get("pairingState") == "paired" and cp.get("tunnelState") != "unavailable":
        print(dev["identifier"] + "\t" + dev.get("deviceProperties", {}).get("name", "?"))
PY
)
  rm -f "$JSON"
  if [ -z "$IDS" ]; then
    echo "✗ 找不到 iPhone／iPad。請解鎖、接上傳輸線或連同一個 Wi-Fi，再執行一次。"
  else
    while IFS=$'\t' read -r ID NAME; do
      if xcrun devicectl device install app --device "$ID" "$APP" >/dev/null 2>&1 < /dev/null; then
        echo "✓ 已安裝到 $NAME"
      else
        echo "✗ 安裝到 $NAME 失敗（手機要解鎖）"
      fi
    done <<< "$IDS"
  fi
fi

# 5. Mac (signed to run on this Mac only; doesn't expire)
if [ "$WHAT" = "all" ] || [ "$WHAT" = "mac" ]; then
  echo "建置 Mac 版…"
  xcodebuild -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards -configuration Release \
     -destination "generic/platform=macOS,variant=Mac Catalyst" -derivedDataPath "$DD" \
     CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
     build > "$LOG" 2>&1 < /dev/null || fail
  MACAPP=$(ls -d "$DD"/Build/Products/Release-maccatalyst/*.app | head -1)
  TARGET="/Applications"
  [ -w "$TARGET" ] || { TARGET="$HOME/Applications"; mkdir -p "$TARGET"; }
  pkill -x "$(basename "$MACAPP" .app)" 2>/dev/null
  rm -rf "$TARGET/方方詞卡.app"
  cp -R "$MACAPP" "$TARGET/方方詞卡.app"
  echo "✓ Mac 版已安裝到 $TARGET/方方詞卡.app"
fi
echo "完成！iPhone／iPad：7 天後再執行一次這個指令就好。Mac 版不會過期。"
