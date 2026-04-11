#!/bin/bash
set -e

FLUTTER_VERSION="3.32.0"
FLUTTER_DIR="$HOME/flutter"

echo "==> Preparing Flutter $FLUTTER_VERSION"
if [ -d "$FLUTTER_DIR/.git" ]; then
  echo "==> Reusing cached Flutter SDK"
  git -C "$FLUTTER_DIR" fetch --depth 1 origin "$FLUTTER_VERSION"
  git -C "$FLUTTER_DIR" checkout -f FETCH_HEAD
else
  rm -rf "$FLUTTER_DIR"
  git clone https://github.com/flutter/flutter.git \
    --depth 1 --branch "$FLUTTER_VERSION" "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

echo "==> Flutter version"
flutter --version

echo "==> Enable web"
flutter config --enable-web

echo "==> Get dependencies"
flutter pub get

echo "==> Build web"
flutter build web --release
