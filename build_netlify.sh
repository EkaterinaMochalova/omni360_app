#!/bin/bash
set -e

FLUTTER_VERSION="3.32.0"
FLUTTER_DIR="$HOME/flutter"

echo "==> Installing Flutter $FLUTTER_VERSION"
git clone https://github.com/flutter/flutter.git \
  --depth 1 --branch "$FLUTTER_VERSION" "$FLUTTER_DIR"

export PATH="$FLUTTER_DIR/bin:$PATH"

echo "==> Flutter version"
flutter --version

echo "==> Enable web"
flutter config --enable-web

echo "==> Get dependencies"
flutter pub get

echo "==> Build web"
flutter build web --release
