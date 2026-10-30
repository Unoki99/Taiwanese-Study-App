#!/bin/bash
# 方方詞卡: builds the app and installs it on your iPhone / iPad and your Mac. No Xcode clicking needed.
#   bash ~/Downloads/fangfang-cards-main/install.sh          iPhone/iPad + Mac
#   bash ~/Downloads/fangfang-cards-main/install.sh ios      only iPhone/iPad
#   bash ~/Downloads/fangfang-cards-main/install.sh mac      only Mac (Apple chip: asks once, iPad app or Mac version; Intel: the Mac version)
#   bash ~/Downloads/fangfang-cards-main/install.sh ipad     only Mac, as the iPad app (Apple chip), and remember that
#   bash ~/Downloads/fangfang-cards-main/install.sh catalyst only Mac, as the Mac version, and remember that
#   bash ~/Downloads/fangfang-cards-main/install.sh ipa      an app file (FangfangCards.ipa on the Desktop) to install with Sideloadly
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
        --exclude "FangfangCards/dict.json" --exclude "FangfangCards/cards.json" "$HERE/" "$DEST/"
  for f in dict.json cards.json; do
    [ -f "$HERE/FangfangCards/$f" ] && cp "$HERE/FangfangCards/$f" "$DEST/FangfangCards/$f"
  done
fi
echo "專案：$DEST/FangfangCards.xcodeproj"

# Xcode new enough? (the project needs Xcode 26, which needs macOS Sequoia 15.6 or later)
XV=$(xcodebuild -version 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
if [ -z "$XV" ]; then
  echo "✗ 找不到 Xcode。請從 App Store 安裝 Xcode，打開一次，再執行這個指令。"; exit 1
elif [ "$XV" -lt 26 ]; then
  echo "✗ 這台 Mac 的 Xcode 是 $(xcodebuild -version | head -1)，太舊了：方方詞卡需要 Xcode 26 以上。"
  echo "  Xcode 26 需要 macOS Sequoia 15.6 以上（這台是 macOS $(sw_vers -productVersion)）。"
  echo "  請先更新 macOS 和 Xcode；如果這台 Mac 不能更新，請用另一台較新的 Mac 安裝。"
  exit 1
fi

# 2. word data (built from the MOE dictionary file if it isn't there yet)
if [ ! -f "$DEST/FangfangCards/dict.json" ] || [ ! -f "$DEST/FangfangCards/cards.json" ]; then
  bash "$DEST/build-data.sh" || { echo "✗ 沒辦法建立詞典資料。"; exit 1; }
fi

# "install.sh ipa": an app file (.ipa) for someone whose Mac can't build the app; they install it on their
# iPhone/iPad with Sideloadly and their own Apple ID (Sideloadly signs it, so it's built unsigned here)
if [ "$WHAT" = "ipa" ]; then
  echo "建置 App 檔（.ipa）…"
  IDD="$DD-ipa"
  xcodebuild -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards -configuration Release \
     -destination "generic/platform=iOS" -derivedDataPath "$IDD" \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
     build > "$LOG" 2>&1 < /dev/null || fail
  APP=$(ls -d "$IDD"/Build/Products/Release-iphoneos/*.app | grep -v -i widget | head -1)
  PKG=$(mktemp -d)
  mkdir -p "$PKG/Payload"
  cp -R "$APP" "$PKG/Payload/"
  OUT="$HOME/Desktop/FangfangCards.ipa"
  rm -f "$OUT"
  (cd "$PKG" && zip -qry "$OUT" Payload)
  rm -rf "$PKG"
  echo "✓ App 檔：$OUT"
  echo "  傳給對方，對方用 Sideloadly 安裝到 iPhone／iPad（見 README「用 Sideloadly 安裝」）。"
  exit 0
fi

# 3. Apple developer team (only needed when the project doesn't have one, e.g. downloaded from GitHub)
TEAMARG=()
IDARG=()
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
  # an app ID of your own: each Apple ID can only use IDs no one else has registered
  FFID="${FANGFANG_ID:-com.fangfangcards.$(echo "$TEAM" | tr 'A-Z' 'a-z')}"
  TEAMARG=(DEVELOPMENT_TEAM="$TEAM" FF_ID="$FFID")
  IDARG=(FF_ID="$FFID")
  # also write it into the project copy, so opening it in Xcode uses the same team and ID
  sed -i '' -e "s/FF_ID = com.unoki99.fangfangcards;/FF_ID = $FFID;/" \
            -e "s/DEVELOPMENT_TEAM = \"\";/DEVELOPMENT_TEAM = $TEAM;/" "$DEST/FangfangCards.xcodeproj/project.pbxproj"
fi

fail() {
  echo "✗ 建置失敗。把下面的錯誤訊息傳給 Claude："
  grep -E "error:|error -|Signing|provision" "$LOG" | sort -u | head -25
  echo "（完整紀錄：${LOG}）"
  exit 1
}

# Build with signing. If the App Group (the widget's shared folder) isn't registered for your Apple ID
# yet, build again without it: the app works normally, only the 分類詞卡 widget has no words.
NOGROUP=()
build_signed() {
  xcodebuild "$@" "${NOGROUP[@]}" build > "$LOG" 2>&1 < /dev/null && return 0
  if [ ${#NOGROUP[@]} -eq 0 ] && grep -q "application-groups" "$LOG"; then
    echo "（你的 Apple ID 還沒註冊這個 App 的 App Group，先不用它建置：App 都正常，只是「分類詞卡」小工具會沒有詞。"
    echo "  想用小工具：在 Xcode 打開 ~/FangfangCards/FangfangCards.xcodeproj，上方選你的 iPhone 按 ▶ 一次，"
    echo "  Xcode 會自動註冊；之後再執行這個指令就好。）"
    NOGROUP=(CODE_SIGN_ENTITLEMENTS="")
    xcodebuild "$@" "${NOGROUP[@]}" build > "$LOG" 2>&1 < /dev/null && return 0
  fi
  return 1
}

# 4. iPhone / iPad (fresh 7-day signature)
if [ "$WHAT" = "all" ] || [ "$WHAT" = "ios" ]; then
  echo "建置 iPhone／iPad 版…（第一次大概 1–2 分鐘）"
  build_signed -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards -configuration Debug \
     -destination "generic/platform=iOS" -derivedDataPath "$DD" -allowProvisioningUpdates "${TEAMARG[@]}" || fail
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

# 5. Mac. On a Mac with an Apple chip: the iPad app itself (exactly the same app as on the iPad; it runs
#    smoother than the Mac version). On an Intel Mac, or with "install.sh catalyst": the Mac version.
# Apple chip: you choose (asked once, remembered in ~/.fangfang-mac-kind; "install.sh ipad" or
# "install.sh catalyst" choose again). Intel: always the Mac version (iPad apps don't run there).
MACKIND="catalyst"
if [ "$(uname -m)" = "arm64" ] || [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then
  KINDFILE="$HOME/.fangfang-mac-kind"
  if [ "$WHAT" = "catalyst" ] || [ "$WHAT" = "ipad" ]; then
    MACKIND="$WHAT"; echo "$MACKIND" > "$KINDFILE"
  elif [ -f "$KINDFILE" ]; then
    MACKIND=$(cat "$KINDFILE")
  elif [ "$WHAT" = "all" ] || [ "$WHAT" = "mac" ]; then
    echo ""
    echo "這台 Mac 是 Apple 晶片，Mac 上要裝哪一種？"
    echo "  1) iPad 版（建議）：跟 iPad 上的一模一樣，比較順，聲調光暈也比較漂亮；7 天後要重新執行這個指令。"
    echo "  2) Mac 版：有側邊欄、可以用選單列；不會過期，但滑鼠移過去放大字的時候比較不順。"
    if [ -t 0 ]; then read -r -p "請輸入 1 或 2（直接按 Enter = 1）：" ANS; else ANS=1; fi
    if [ "$ANS" = "2" ]; then MACKIND="catalyst"; else MACKIND="ipad"; fi
    echo "$MACKIND" > "$KINDFILE"
    echo "（記住了。之後想換：install.sh ipad 或 install.sh catalyst）"
  else
    MACKIND="ipad"
  fi
  [ "$MACKIND" = "ipad" ] || MACKIND="catalyst"
elif [ "$WHAT" = "ipad" ]; then
  echo "✗ 這台 Mac 是 Intel 晶片，不能執行 iPad App，改裝 Mac 版。"
fi
if [ "$WHAT" = "all" ] || [ "$WHAT" = "mac" ] || [ "$WHAT" = "catalyst" ] || [ "$WHAT" = "ipad" ]; then
  TARGET="/Applications"
  [ -w "$TARGET" ] || { TARGET="$HOME/Applications"; mkdir -p "$TARGET"; }
  if [ "$MACKIND" = "ipad" ]; then
    echo "建置 Mac 版（iPad App）…"
    MDD="$DD-ipadmac"
    # the project is set up for the Mac version; for this build, switch it to "iPad app on the Mac"
    # (in the copy in ~/FangfangCards; put back right after)
    PBX="$DEST/FangfangCards.xcodeproj/project.pbxproj"
    cp "$PBX" "$PBX.fangfang-bak"
    sed -i '' -e 's/SUPPORTS_MACCATALYST = YES;/SUPPORTS_MACCATALYST = NO;/' \
              -e 's/SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;/SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES;/' "$PBX"
    restore() { mv -f "$PBX.fangfang-bak" "$PBX"; }
    # this Mac as an "iPad app" destination
    xcodebuild -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards -showdestinations > "$LOG" 2>&1 < /dev/null
    LINE=$(sed '/Ineligible/,$d' "$LOG" | grep "Designed for" | grep "id:" | head -1)
    DID=$(echo "$LINE" | grep -oE 'id:[^,} ]+' | head -1 | cut -d: -f2)
    # (the variant name "Designed for [iPad,iPhone]" has a comma xcodebuild can't read, so: this Mac's id +
    #  arm64; with the Mac version switched off above, that is the iPad-app destination)
    if [ -n "$DID" ]; then DESTSPEC="platform=macOS,arch=arm64,id=$DID"
    else DESTSPEC="platform=macOS,arch=arm64,variant=Designed for iPad"; fi
    SHOWD=$(grep -E "platform:macOS" "$LOG" | head -5)
    build_signed -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards -configuration Debug \
         -destination "$DESTSPEC" -derivedDataPath "$MDD" \
         -allowProvisioningUpdates -allowProvisioningDeviceRegistration "${TEAMARG[@]}" \
         || { restore; echo "（可以用的目的地：）"; echo "$SHOWD"; fail; }
    restore
    IPAPP=$(ls -d "$MDD"/Build/Products/Debug-iphoneos/*.app | grep -v -i widget | head -1)
    NAME=$(basename "$IPAPP")
    pkill -f "方方詞卡.app" 2>/dev/null
    # an iPad app on the Mac lives inside a wrapper: 方方詞卡.app/Wrapper/<app>.app (+ WrappedBundle link).
    # Keep the wrapper and only swap the app inside it, and take off any "downloaded from the internet"
    # marks, so the Mac hopefully remembers that you allowed it to open.
    if [ ! -L "$TARGET/方方詞卡.app/WrappedBundle" ]; then rm -rf "$TARGET/方方詞卡.app"; fi
    mkdir -p "$TARGET/方方詞卡.app/Wrapper"
    rm -rf "$TARGET/方方詞卡.app/Wrapper/$NAME"
    cp -R "$IPAPP" "$TARGET/方方詞卡.app/Wrapper/$NAME"
    ln -sfn "Wrapper/$NAME" "$TARGET/方方詞卡.app/WrappedBundle"
    xattr -cr "$TARGET/方方詞卡.app" 2>/dev/null
    echo "✓ Mac 版（iPad App）已安裝到 $TARGET/方方詞卡.app"
    echo "  跟 iPhone／iPad 一樣，免費 Apple ID 的話 7 天後再執行一次這個指令。"
  else
    echo "建置 Mac 版…"
    xcodebuild -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards -configuration Release \
       -destination "generic/platform=macOS,variant=Mac Catalyst" -derivedDataPath "$DD" \
       CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" "${IDARG[@]}" \
       build > "$LOG" 2>&1 < /dev/null || fail
    MACAPP=$(ls -d "$DD"/Build/Products/Release-maccatalyst/*.app | head -1)
    pkill -x "$(basename "$MACAPP" .app)" 2>/dev/null
    rm -rf "$TARGET/方方詞卡.app"
    cp -R "$MACAPP" "$TARGET/方方詞卡.app"
    echo "✓ Mac 版已安裝到 $TARGET/方方詞卡.app"
  fi
fi
echo "完成！免費 Apple ID：7 天後再執行一次這個指令就好。"
