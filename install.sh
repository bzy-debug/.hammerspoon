set -xeuo pipefail

mkdir -p ./Spoons

spoons=("BingDaily" "EmmyLua" "LeftRightHotkey")

for spoon in "${spoons[@]}"; do
  if [ -d "./Spoons/${spoon}.spoon" ]; then
    echo "${spoon}.spoon is already installed, skipping..."
    continue
  fi

  wget "https://github.com/Hammerspoon/Spoons/raw/master/Spoons/${spoon}.spoon.zip"
  unzip "${spoon}.spoon.zip" -d ./Spoons/
  rm "${spoon}.spoon.zip"
done

ln -sf ./.aerospace.toml ~/.aerospace.toml