set -xeuo pipefail

mkdir -p ./Spoons

spoons=("BingDaily" "EmmyLua" "LeftRightHotkey")

for spoon in "${spoons[@]}"; do
  wget "https://github.com/Hammerspoon/Spoons/raw/master/Spoons/${spoon}.spoon.zip"
  unzip "${spoon}.spoon.zip" -d ./Spoons/
done

ln -sf ./.aerospace.toml ~/.aerospace.toml