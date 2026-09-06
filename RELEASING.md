# Releasing Apidae

How a version gets from `main` to something people can download. Two paths: unsigned (works today) and signed (once the Apple Developer account exists). The same pipeline handles both; it decides by whether the signing secrets are set.

## Every release

1. Make sure `main` is green in CI and the app has been run from a clean build on at least one Mac.
2. Bump the version in three places and keep them in step:
   - `Apidae/Info.plist`: `CFBundleShortVersionString` (e.g. `0.3.0`) and `CFBundleVersion` (build number, goes up by one each release).
   - `homebrew/Casks/apidae.rb`: `version`.
   - `CHANGELOG.md`: turn the `[Unreleased]` heading into `[x.y.z] - YYYY-MM-DD`.
3. Read the README once and check every claim still matches the app: features, settings paths, permission names, test count, architecture tree.
4. Commit, then tag `vX.Y.Z` on that commit. In GitHub Desktop, the tagged commit in History shows a tag badge with an up arrow; Push origin then sends the tag with the branch. If the badge is missing, right click the commit, Create Tag, and push. If a tag ever reaches GitHub without starting a build, open Actions > Release > Run workflow and enter the tag.
5. `release.yml` runs on the tag: builds Release, signs (Developer ID if secrets exist, otherwise ad hoc), packages `Apidae.dmg`, notarises when it can, and creates the GitHub Release with the DMG attached. Unsigned builds are marked as pre releases and carry Gatekeeper instructions in the notes.
6. Download the DMG from the release page and test it on a Mac that has never had Apidae installed. First run should show onboarding, ask for Accessibility, and keep awake should start watching Claude straight away.
7. Only then share the link.

## First public release checklist (one off)

- [ ] Repo set to public on GitHub (Settings > General > Danger Zone > Change visibility). Public repos also get free macOS Actions minutes; private ones burn them at ten times the rate.
- [ ] Repo description and topics set (macos, menu-bar, claude, keep-awake, swift, swiftui).
- [ ] Screenshots in the README: menu bar status line while Claude is busy, the cover on a display, the Stats tab.
- [ ] Onboarding run through on a fresh macOS user account.
- [ ] `getapidae.com` has at least a landing page with a download button. Note that `releases/latest` skips pre releases, so link to the releases page (or a specific tag) until the first signed release; switch to `releases/latest` after that.

## Signed releases (once the Developer account exists)

Enrol in the Apple Developer Program. Enrolling as an organisation (Metserve Media) puts the company name on the certificate and covers future apps, but needs a D-U-N-S number and takes longer; enrolling as an individual is quicker and can be migrated later.

Then, in Xcode or developer.apple.com, create a **Developer ID Application** certificate and export it as a `.p12` with a password. Create an app specific password for your Apple ID at appleid.apple.com. Add these repository secrets (Settings > Secrets and variables > Actions):

| Secret | Value |
|---|---|
| `CERTIFICATE_P12_BASE64` | `base64 -i DeveloperID.p12 \| pbcopy` |
| `CERTIFICATE_PASSWORD` | the `.p12` password |
| `DEVELOPER_ID_APPLICATION` | `Developer ID Application: Name (TEAMID)` |
| `NOTARIZE_APPLE_ID` | the Apple ID email |
| `NOTARIZE_PASSWORD` | the app specific password |
| `APPLE_TEAM_ID` | the 10 character team id |

Fill the three `TODO` values at the top of `scripts/build-release.sh` so local release builds match. Then re tag (or tag the next version) and the pipeline will sign, notarise and staple without any other change. After the first signed release:

- [ ] Replace `sha256 :no_check` in the cask with the real hash (`shasum -a 256 Apidae.dmg`).
- [ ] Create the `MrADeveci/homebrew-apidae` tap repo containing `Casks/apidae.rb`, and update the install command in `homebrew/README.md` and the README.
- [ ] Consider bringing Sparkle back for in app updates. It needs a freshly generated ed25519 key (never the old Lockpaw key) and an appcast hosted at `getapidae.com/appcast.xml`.

## Why signing matters here

Apidae asks for Accessibility and Input Monitoring. An unsigned download adds a Gatekeeper warning on top of those two prompts, and with ad hoc signing macOS ties the permission grants to the exact build, so every update makes users grant them again. A Developer ID signature removes the warning and keeps permissions across updates.
