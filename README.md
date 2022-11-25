<h1 align="center">BetterTG</h1>
<p align="center">
A Telegram client for iOS and watchOS
</p>

# Currently implemented
## iOS
- login
- fixed amount of chats/messages with people (only)
- sending/reading text messages
## watchOS
- login
- fixed amount of chats/messages
- sending/reading text messages

# Installation
## iOS
Download an ipa from release tab and install through [Sideloadly](https://altstore.io) or [AltStore](https://altstore.io).
## watchOS
There is a bug compiling TDLibKit for real Apple Watch at the moment.\
Only possible way is to run on a Simulator.

# Contributing
You can contribute **any** change you want to!
## Step 1 - Clone the repo
```shell
git clone --recurse-submodules https://github.com/levochkaa/BetterTG.git
```
## Step 2 - Download XCode
Latest **Xcode 14 beta** versions are used for this project.\
I suggest using [**Xcodes**](https://github.com/RobotsAndPencils/XcodesApp) for downloading.
## Step 3 - `api_id` and `api_hash`
Go to [this site](https://my.telegram.org/).\
Log in, open **API development tools**, fill up the info.\
Then click **Save changes**
at the bottom of the page. \
Leave the page **open** for the next step.
## Step 4 - Development environment
You need to have [Homebrew](https://brew.sh) installed. \
Now run these commands:
```shell
brew install swift-sh
sudo chmod +x environment.swift
sudo chmod +x gyb.sh
./environment.swift <api_id> <api_hash>
```
Everything is set up now! **GL HF**
