#!/bin/bash

# Extract version from pubspec.yaml
VERSION=$(grep "^version:" pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
PACKAGE_NAME="eomstart_${VERSION}_amd64"
DEB_DIR="build/debian/$PACKAGE_NAME"

echo "Packaging version $VERSION..."

# Clean old deb build dir
rm -rf build/debian
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/opt/eomstart"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/usr/share/icons/hicolor/scalable/apps"

# Create control file
cat << EOF > "$DEB_DIR/DEBIAN/control"
Package: eomstart
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Maintainer: eom <contact@eom.kz>
Description: EOM START
 Micro mobility app for EOM
EOF

# Copy app files
cp -r build/linux/x64/release/bundle/* "$DEB_DIR/opt/eomstart/"

# Create executable wrapper
cat << 'EOF' > "$DEB_DIR/usr/bin/eomstart"
#!/bin/sh
cd /opt/eomstart
exec ./eomstart "$@"
EOF
chmod +x "$DEB_DIR/usr/bin/eomstart"

# Create desktop file
cat << EOF > "$DEB_DIR/usr/share/applications/eomstart.desktop"
[Desktop Entry]
Version=$VERSION
Name=eomstart
GenericName=micro mobility app
Comment=EOM START
Exec=eomstart
Terminal=false
Type=Application
Categories=Utility;
Keywords=Flutter;
Icon=eomstart
EOF

# Check if svg icon exists and copy it
if [ -f "debian/gui/micro_mobility_app.svg" ]; then
    cp debian/gui/micro_mobility_app.svg "$DEB_DIR/usr/share/icons/hicolor/scalable/apps/eomstart.svg"
else
    # if there is an icon.png, we can use it
    if [ -f "assets/icon.png" ]; then
        mkdir -p "$DEB_DIR/usr/share/icons/hicolor/512x512/apps"
        cp assets/icon.png "$DEB_DIR/usr/share/icons/hicolor/512x512/apps/eomstart.png"
    fi
fi

# Set permissions
chmod -R 0755 "$DEB_DIR"

# Build deb
dpkg-deb --build "$DEB_DIR"
mv "build/debian/${PACKAGE_NAME}.deb" "./${PACKAGE_NAME}.deb"

echo "Done! Package ./${PACKAGE_NAME}.deb has been created."
