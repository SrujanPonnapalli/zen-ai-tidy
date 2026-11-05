# Zen AI Tidy

Arc had a button that looked at your messy pile of tabs and sorted them into named groups. Zen AI Tidy brings that to [Zen Browser](https://zen-browser.app). Click **Tidy** and the loose tabs in your current space get filed into folders like "Machine Learning", "Japan Trip" or "Home Buying".

The sorting runs on Apple Intelligence, on your Mac. There's no API key to set up, and your tab titles never leave the machine.

## What it does

Hover the sidebar and a small paintbrush labelled **Tidy** shows up on the divider between your pinned and unpinned tabs, next to Zen's own clear button. Click it and, after 10 to 20 seconds, your loose tabs move into folders. If a tab fits a folder you already have, it goes there instead of into a new one. Tabs that don't share a topic with anything else stay where they are.

Right after a tidy the button turns into **Undo**, which puts every tab back and removes the folders it made. It only lasts until you switch to another tab.

The same action is in the space's right-click menu as **Tidy Tabs**, which is handy when a space has no pinned tabs and Zen hides the divider.

Pinned tabs, Essentials and tabs already inside a folder are never touched.

## Requirements

You need an Apple silicon Mac on macOS 26 or later with Apple Intelligence turned on (System Settings, then Apple Intelligence & Siri). The helper is compiled on your machine, so Xcode 26 or newer has to be installed as well.

Zen doesn't run custom scripts out of the box. You need a script loader, and [Sine](https://github.com/CosmoCreeper/Sine) is the easiest one to set up. Plain [fx-autoconfig](https://github.com/MrOtherGuy/fx-autoconfig) works too.

## Install

There are two parts: a small command-line helper that talks to Apple's on-device model, and the Zen script that adds the button.

### 1. Install the helper with Homebrew

```bash
brew tap SrujanPonnapalli/zen-ai-tidy https://github.com/SrujanPonnapalli/zen-ai-tidy
```

Recent versions of Homebrew won't load a formula from a third-party tap until you trust it:

```bash
brew trust --formula srujanponnapalli/zen-ai-tidy/tidy-helper
```

```bash
brew install tidy-helper
```

Homebrew builds it from source, which takes a few seconds and avoids any code-signing prompts. To check that your Mac can run the model:

```bash
tidy-helper --check
```

It should print `available`. If it says the model is unavailable, Apple Intelligence is off or still downloading.

### 2. Install the mod with Sine

1. Open Zen's settings and go to the Sine section.
2. Turn on **Allow unsafe JS**. Sine asks for this for any mod that isn't in its store.
3. Add a mod from a repository and enter `SrujanPonnapalli/zen-ai-tidy`.
4. Restart Zen.

If the button says **Helper not installed**, step 1 didn't finish, or Homebrew lives somewhere other than `/opt/homebrew` or `/usr/local`.

### Without Sine

`install.sh` is the setup I use while working on this. It builds the helper, copies fx-autoconfig into `Zen.app`, and symlinks the script and helper into your default Zen profile, so changes in the repo show up the next time Zen starts.

```bash
git clone https://github.com/SrujanPonnapalli/zen-ai-tidy && cd zen-ai-tidy && ./install.sh
```

Zen updates wipe the loader from the app bundle, so run it again after each update. Don't use this and the Sine mod at the same time, or the script loads twice and you get two buttons.

## How the grouping works

The Zen script collects the title and site of each loose tab, plus the names of any folders already in the space, and pipes them as JSON to `tidy-helper`. The helper is about 130 lines of Swift on top of Apple's Foundation Models framework.

Apple's on-device model is small (around 3 billion parameters) and has a context window of roughly 4,000 tokens, so asking it to sort 40 tabs in one go gives poor results. The helper works in two passes instead:

1. It labels each tab with a broad topic, the sort of thing you'd write on a folder: "Cooking" rather than "Butter Chicken recipe". Large sets of tabs go in evenly sized batches of up to 40.
2. It looks at all the topic names at once and merges the ones that mean the same thing, so "Mortgages" and "Real Estate" both end up in "Home Buying".

Both passes use guided generation, which makes the model return structured data instead of free text, and greedy decoding, so the same tabs give the same folders every time. A new folder needs at least two tabs; a tab can still join an existing folder on its own.

The repo includes a small benchmark of 20 and 46 hand-labelled tabs. The current prompts score an F1 of 0.81 and 0.87 on them, counting pairs of tabs that should or shouldn't share a folder.

## Limits

Zen keeps folders in the pinned part of a space, so tidied tabs become pinned tabs. That's how every Zen folder works, but it means pinned-tab behaviour applies, such as the button that resets a tab to its original URL.

A tidy takes 10 to 20 seconds. Tabs you close or move while it runs are skipped.

The script relies on Zen internals (`gZenFolders`, `gZenWorkspaces`) that aren't a public API. It was built against Zen 1.24b, and a future Zen release could break it.

The model makes judgement calls you might disagree with. In testing it sometimes put fantasy football under "Sports" and a mortgage calculator under "Finance".

## Troubleshooting

When a tidy fails, the button shows **Couldn't tidy** for a few seconds and the error is written to `zen-ai-tidy.log` in your Zen profile folder. You can find the profile folder from Zen's `about:profiles` page. The full error also appears in the Browser Console (Tools, then Browser Tools).

To see exactly how the model labelled and merged a set of tabs, run the helper with debugging on:

```bash
TIDY_DEBUG=1 tidy-helper < test/big-tabs.json
```

## Development

```bash
swiftc -O helper/main.swift -o bin/tidy-helper
```

```bash
python3 test/eval.py
```

The first command builds the helper. The second runs both test sets and prints the scores along with the folders it produced, so you can see what a prompt change did before trying it in Zen.

| Path | What it is |
| --- | --- |
| `helper/main.swift` | The helper: reads tabs as JSON on stdin, prints folders as JSON |
| `chrome/JS/zen-ai-tidy.uc.mjs` | The Zen script: button, menu item, folder creation and undo |
| `theme.json` | Sine mod manifest |
| `Formula/tidy-helper.rb` | Homebrew formula |
| `install.sh` | Manual install without Sine |
| `test/` | Labelled tab sets and the scoring script |

## Credits

The idea comes from Arc's Tidy Tabs. [Ai-TabGroups-ZenBrowser](https://github.com/Darsh-A/Ai-TabGroups-ZenBrowser) did this first, using Gemini or Ollama, back when Zen still had tab groups instead of folders. The script loads through [fx-autoconfig](https://github.com/MrOtherGuy/fx-autoconfig) or [Sine](https://github.com/CosmoCreeper/Sine).

MIT licensed. See [LICENSE](LICENSE).
