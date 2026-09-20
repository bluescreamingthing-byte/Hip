# Minecraft 1.0 for iPhone - cloud build (no Mac needed)

This project builds one iPhone app that opens straight into Minecraft 1.0 (no launcher screens). It is a small
patch on top of the open-source **Amethyst-iOS** project, which is what lets a desktop Java game run on an iPhone.
GitHub's free Mac machines do the building, so everything below happens in a web browser.

## Honest status

- **Not tested.** I could not run any of this on a Mac or an iPhone. The first cloud build may fail with a compile
  error. If it does, send me the text from the failed step (or the `build-log` file) and I will fix it.
- Amethyst has code for iOS 26 (including the newer-chip JIT handshake), but I could not confirm it works on
  iOS 26.5.1 with an iPhone 17. That is the biggest unknown.

## Step 1 - Build the app on GitHub

1. Make a free account at github.com and create a **new repository**. Choose **Public** (public repositories get
   the Mac build machines for free; private ones use up a small monthly allowance very fast).
2. Upload everything from this folder: click **Add file > Upload files** and drag the files in, including the
   `.github` folder. If GitHub does not accept the `.github` folder, click **Add file > Create new file**, type
   `.github/workflows/build.yml` as the name, and paste in the contents of `workflow-copy-paste-this.txt`.
   Then commit.
3. Open the **Actions** tab, click **Build Minecraft 1.0 for iPhone** on the left, then **Run workflow**.
4. Wait (roughly 30 to 60 minutes). When it turns green, open the run and download the **Minecraft_1_0_ios**
   file at the bottom. Unzip it to get `Minecraft_1_0_ios.ipa`.

Do not upload Minecraft-1.0.jar to the repository. It is Mojang's game, and a public repository would be sharing it.

## Step 2 - Install it on the iPhone

You need a computer for this step, but it can be a Windows PC. Do not install the raw `.ipa` directly: iOS shows an
"integrity could not be verified" style message for an app whose signature is not valid for your phone. Use
**AltStore**, **SideStore** or **Sideloadly**: they re-sign the app with your own Apple ID when they install it.
With a free Apple ID the app expires after 7 days and has to be re-signed. TrollStore does not support your iOS
version.

## Step 3 - Set up JIT (needed every time you play)

Install **StikDebug** and follow its own setup guide (it needs a one-time pairing with a computer). The Minecraft 1.0
app then asks StikDebug to turn JIT on for it automatically.

## Step 4 - First launch

1. Put `Minecraft-1.0.jar` where the iPhone can reach it (AirDrop it to yourself, or save it in iCloud Drive or the
   Files app).
2. Open **Minecraft 1.0**. It asks for the jar: tap **Choose Minecraft-1.0.jar** and pick it. This happens once.
3. It asks for a **player name** (letters, digits and underscore; every player on a server needs a different one).
4. It shows "Waiting for JIT..." and opens StikDebug. Allow it and come back. The game then starts by itself.

If it says a **legacy script** is being used: open StikDebug, long-press the app, tap **Assign Script**, pick
`UniversalJIT26.js` from the app's folder in the Files app, then launch again.

## Notes

- **Sound:** expect none. Minecraft 1.0's own sound download source no longer exists.
- **Controls:** the stock Amethyst on-screen controls (editable from the in-game menu).
- **Quitting:** after you exit the game you may land in Amethyst's normal launcher screens. Just close the app.
- **Multiplayer:** 1.0 can only join 1.0 servers, and only with `online-mode=false` in the server's
  `server.properties`.
- **Legal:** Amethyst-iOS is GPLv3, so if you share a build you must share the source of your changes (this patch
  and `BundledGame.*`). Keep `Minecraft-1.0.jar` private.
