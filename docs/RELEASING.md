# Releasing

Releases are built on a Mac and uploaded by hand with the GitHub CLI.

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, then commit.
2. Build a universal Release app (ad-hoc signed):

   ```sh
   xcodegen generate
   xcodebuild -project Playtation.xcodeproj -scheme Playtation -configuration Release \
     -derivedDataPath build clean build
   ```

3. Zip it so macOS keeps the signature and resource forks:

   ```sh
   ditto -c -k --sequesterRsrc --keepParent build/Build/Products/Release/Playtation.app Playtation-1.0-macOS.zip
   shasum -a 256 Playtation-1.0-macOS.zip > Playtation-1.0-macOS.zip.sha256
   ```

4. Publish:

   ```sh
   gh release create v1.0 Playtation-1.0-macOS.zip Playtation-1.0-macOS.zip.sha256 \
     --title "Playtation 1.0" --notes-file RELEASE_NOTES.md
   ```

The app is not notarized, so users see a Gatekeeper warning on first launch. The release notes explain the
workaround. Notarizing needs an Apple Developer account; when you have one, sign with a Developer ID
certificate and run `xcrun notarytool` before zipping.
