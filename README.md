<div align="center">
    <img src="https://github.com/levochkaa/BetterTG/blob/main/BetterTG/Assets.xcassets/AppIcon_README.imageset/bettertg256.png?raw=true" alt="AppIcon">
</div>
<h1 align="center">BetterTG</h1>
<p align="center">A Telegram client for iOS</p>

![](https://img.shields.io/badge/platform-iOS-000000?style=flat&logo=apple&logoColor=white)
![](https://img.shields.io/badge/minimum%20OS-iOS%2016-blueviolet?style=flat&logo=apple&logoColor=white)
![](https://img.shields.io/badge/Swift%205.7-FA7343?style=flat&logo=swift&logoColor=white)
![](https://img.shields.io/badge/SwiftUI-2E00F1?style=flat&logo=swift&logoColor=white)
![](https://img.shields.io/badge/Telegram-2CA5E0?style=flat&logo=telegram&logoColor=white)
[![GPLv3 License](https://img.shields.io/badge/License-GPL%20v3-yellow.svg?style=flat)](https://opensource.org/licenses/)

# Currently implemented

- login
- all chats with people from main folder/archive
- sending/reading text/photo/voice/album messages
- replying to/editing messages
- draft, forwarded from
- animojis (tgs, webp, sometimes webm)
- pinned chats
- searching your/global chats
- custom settings sheet
- unique UI
- last seen online
- formatting/formatted messages
- live activity with opened chat

# Road Map

[GitHub Project](https://github.com/users/levochkaa/projects/1/views/1)

# Installation

Download an .ipa file from [releases tab](https://github.com/levochkaa/BetterTG/releases/latest) and install through [Sideloadly](https://altstore.io)
or [AltStore (suggested)](https://altstore.io).

**Soon, I will buy Paid Apple Developer account, I promise.**

# Screenshots

<span><img src=".github/images/screenshots/1.PNG" alt="screenshots/1" width="200px"></span>
<span><img src=".github/images/screenshots/2.PNG" alt="screenshots/2" width="200px"></span>
<span><img src=".github/images/screenshots/3.PNG" alt="screenshots/3" width="200px"></span>
<span><img src=".github/images/screenshots/4.PNG" alt="screenshots/4" width="200px"></span>
<span><img src=".github/images/screenshots/5.PNG" alt="screenshots/5" width="200px"></span>
<span><img src=".github/images/screenshots/6.PNG" alt="screenshots/6" width="200px"></span>
<span><img src=".github/images/screenshots/7.PNG" alt="screenshots/7" width="200px"></span>
<span><img src=".github/images/screenshots/8.PNG" alt="screenshots/8" width="200px"></span>
<span><img src=".github/images/screenshots/9.PNG" alt="screenshots/9" width="200px"></span>
<span><img src=".github/images/screenshots/10.PNG" alt="screenshots/10" width="200px"></span>
<span><img src=".github/images/screenshots/11.PNG" alt="screenshots/11" width="200px"></span>
<span><img src=".github/images/screenshots/12.PNG" alt="screenshots/12" width="200px"></span>
<span><img src=".github/images/screenshots/13.PNG" alt="screenshots/13" width="200px"></span>
<span><img src=".github/images/screenshots/14.PNG" alt="screenshots/14" width="200px"></span>
<span><img src=".github/images/screenshots/15.PNG" alt="screenshots/15" width="200px"></span>
<span><img src=".github/images/screenshots/16.PNG" alt="screenshots/16" width="200px"></span>
<span><img src=".github/images/screenshots/17.PNG" alt="screenshots/17" width="200px"></span>
<span><img src=".github/images/screenshots/18.PNG" alt="screenshots/18" width="200px"></span>

# Contributing

You can contribute **any** change you want to!

**But, if you are intreseted in the project Road Map, check this [GitHub Project](https://github.com/users/levochkaa/projects/1/views/1)**

## Step 1 - Clone the repo

```shell
git clone https://github.com/levochkaa/BetterTG.git
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
