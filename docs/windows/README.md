# Embers for Windows

Completes Discord **game quests** ("play a game for 15 minutes") without installing the games.
Click a cover and Discord thinks you are playing. On first launch the app asks for your language (English is the default) and
remembers it. You can switch any time with the **EN / RU** button in the top bar.

> **Video (ad) quests do not work.** Quests like "Watch a video, get 200 Orbs" can't be completed
> with Embers. It only handles quests that ask you to **play a game**.

## Install

1. Extract the whole archive anywhere (for example `C:\Embers`). Don't run it from inside the zip.
2. Open the `Embers` folder and double-click **`Embers.exe`**.
3. If Windows shows **"Windows protected your PC"**: click **More info → Run anyway**.
   The app isn't signed with a paid certificate yet, so SmartScreen warns about every new app.
   This is needed only once.

Requirements: Windows 10 or 11 (64-bit) and the **Discord desktop app** (the browser version
doesn't detect games).

## How to use

1. In Discord open **Quests** and press **Accept quest** on the quests you want. Only accepted
   quests make progress. Note the game name, for example "Play **EVE Online** for 15 minutes".
2. Make sure **Discord → Settings → Activity Privacy → Share your activity** is on.
3. In Embers find the game (search, or the "Often in quests" row) and **click its cover**.
   Discord shows the game as running within 5–10 seconds.
4. Leave Discord open until the timer is done, then claim your reward in Discord.
   You can minimize Embers and keep using your PC. **Don't close the Embers window while a
   quest is running**: closing it stops all games.

## Queue

For several quests at once, don't switch games by hand:

1. Hover a cover and click **+** on every game you need.
2. A **Queue** list appears. Pick the time for each game (5 minutes to 2 hours) and drag the order
   with the arrows.
3. Click **Start queue**.

The games then run one by one: a game runs for its time plus 45 seconds as a safety margin, then
a 5 second pause, then the next game. **Skip** jumps to the next game, **Stop queue** ends it.
The queue is not saved: it lives only while the app is open, and closing the app clears it.

## Tips

- Keep your PC awake for long quests: a sleeping PC stops everything (a turned-off screen is fine).
  Use *Settings → System → Power → Screen and sleep*, or PowerToys Awake.
- Game not in the list? Press the refresh button in the top right. The list is Discord's own
  public game database and updates by itself once a day.
- If Discord doesn't see the game, wait 10–15 seconds, then check that the desktop Discord app is
  open and "Share your activity" is on.
- Windows Defender may scan the small helper program the app creates for each game. If it is
  blocked, allow `%APPDATA%\Embers\fake` in Defender's exclusions.

## How it works

Discord looks at the processes on your PC and compares their file names with its public game
database. Embers copies a tiny empty program (`fakegame.exe`, source in `Windows/helper`) to
`%APPDATA%\Embers\fake\<game>\...` under the same file name as the game, for example
`games\starrail.exe`, and runs it. Discord finds the match and reports the quest progress itself.

## Disclaimer

Unofficial tool, not affiliated with Discord. Using it may violate Discord's Terms of Service, and
your account could be warned or banned. You use it at your own risk. Game names and covers belong
to their owners; covers are loaded from Discord's CDN while the app runs.
