<img src="https://github.com/levochkaa/BetterTG/blob/main/BetterTG/Assets.xcassets/AppIcon.appiconset/bettertg.png?raw=true" 
width="256" height="256" 
style="border-radius: 45px; display: block; margin: auto;" 
alt="AppIcon">
<h1 style="text-align: center;">BetterTG</h1>
<p style="text-align: center;">A Telegram client for iOS</p>

![](https://img.shields.io/badge/platform-iOS-000000?style=flat&logo=apple&logoColor=white)
![](https://img.shields.io/badge/minimum%20OS-iOS%2016-blueviolet?style=flat&logo=apple&logoColor=white)
![](https://img.shields.io/badge/Swift%205.7-FA7343?style=flat&logo=swift&logoColor=white)
![](https://img.shields.io/badge/SwiftUI-2E00F1?style=flat&logo=swift&logoColor=white)
![](https://img.shields.io/badge/Telegram-2CA5E0?style=flat&logo=telegram&logoColor=white)
[![GPLv3 License](https://img.shields.io/badge/License-GPL%20v3-yellow.svg?style=flat)](https://opensource.org/licenses/)

# Currently implemented

- login
- all chats with people from main folder
- sending/reading text messages
- replying to messages
- chat draft
- editing messages

# Installation

Download an ipa from release tab and install through [Sideloadly](https://altstore.io)
or [AltStore](https://altstore.io).

# Contributing

You can contribute **any** change you want to!

## Step 1 - Clone the repo

```shell
git clone --recurse-submodules https://github.com/levochkaa/BetterTG.git
```

## Step 2 - Download XCode

Latest **Xcode 14 beta** versions are used for this project.\
I suggest using [**Xcodes**](https://github.com/RobotsAndPencils/XcodesApp) for downloading XCode.

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
