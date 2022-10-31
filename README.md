<h1 align="center">BetterTG</h1>
<p align="center">
A Telegram client for iOS and watchOS
</p>

# Currently implemented
## iOS
- **nothing**
## watchOS
- fixed amount of main chats
- fixed amount of messages list
- sending text messages
- reading text messages

# Installation
No way except for building on your own mac for contributing

# Contributing
You can contribute **any** change you want to, I'm happy with any PR!
## Step 1 - Clone the repo
```shell
git clone --recurse-submodules https://github.com/levochkaa/BetterTG.git
```
## Step 2 - Download XCode
I'm using latest **Xcode 14 beta** versions. I suggest using [**Xcodes**](https://github.com/RobotsAndPencils/XcodesApp) for downloading.
## Step 3 - `api_id` and `api_hash`
Go to [this site](https://my.telegram.org/). Log in, open **API development tools**, fill up the info. Then click **Save changes**
at the bottom of the page. \
Leave the page **open** for the next step.
## Step 4 - Dev env
You need to have [Homebrew](https://brew.sh) installed. \
Now run these commands:
```shell
brew install swift-sh
sudo chmod +x environment.swift
sudo chmod +x gyb.sh
./environment.swift <api_id> <api_hash>
```
Everything is set up now! **GL HF**
