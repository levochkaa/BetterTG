// FFmpegVODShortVideoProbeFixture.swift

#if DEBUG
    import Foundation

    /// A real 2-second VP9 track with 10.008 seconds of Opus, including the tail.
    /// ffmpeg -f lavfi -i color=c=blue:s=64x36:r=10:d=2
    /// -f lavfi -i anullsrc=r=48000:cl=mono:d=10 -c:v libvpx-vp9 -b:v 20k
    /// -g 10 -c:a libopus -b:a 6k -map_metadata -1 output.webm
    enum FFmpegVODShortVideoProbeFixture {
        static let sha256 = "fc057ec7fdbeb41f53aae187ab72444742f02d96140189fafe6bc391e70f8b6f"

        private static let encoded = [
            "GkXfo59ChoEBQveBAULygQRC84EIQoKEd2VibUKHgQRChYECGFOAZwEAAAAAABwpEU2bdLpNu4tTq4QVSalmU6yBoU27i1OrhBZUrmtTrIHWTbuMU6uEElTD",
            "Z1OsggGkTbuMU6uEHFO7a1OsghwA7AEAAAAAAABZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVSalmsCrXsYMPQkBNgIxMYXZmNjMuMS4xMDJXQYxMYXZmNjMuMS4xMDJEiYhAw4wAAAAAABZUrmtAyK4B",
            "AAAAAAAATteBAXPFiBrZfwmbJkONnIEAIrWcg3VuZIiBAIaFVl9WUDmDgQEj44OEBfXhAOCQsIFAuoEkmoECVbCEVbmBAVXugQDsAQAAAAAAAAIAAK4BAAAA",
            "AAAAaNeBAnPFiKRggaT0JMpMnIEAIrWcg3VuZIiBAIaGQV9PUFVTVqqDYy6gVruEBMS0AIOBAiPjg4QBMS0A4ZGfgQG1iEDncAAAAAAAYmSBEFXugQBjopNP",
            "cHVzSGVhZAEBOAGAuwAAAAAAElTDZ0DXc3OfY8CAZ8iZRaOHRU5DT0RFUkSHjExhdmY2My4xLjEwMnNz2WPAi2PFiBrZfwmbJkONZ8ikRaOHRU5DT0RFUkSH",
            "l0xhdmM2My4xLjEwMiBsaWJ2cHgtdnA5Z8ihRaOIRFVSQVRJT05Eh5MwMDowMDowMi4wMDAwMDAwMDAAc3PWY8CLY8WIpGCBpPQkykxnyKFFo4dFTkNPREVS",
            "RIeUTGF2YzYzLjEuMTAyIGxpYm9wdXNnyKFFo4hEVVJBVElPTkSHkzAwOjAwOjEwLjAwODAwMDAwMAAfQ7Z1TYrngQCji4IAAIAIC+Y7I6tgo66BAACAgkmD",
            "QgAD8AI2ADgkHBhCAAAwYAAAXkf//5qZgf////+xTAv////jpIAAo4qCABWACAissw7Go4qCACmACAissw7Go4qCAD2ACAissw7Go4qCAFGACAissw7Go4qC",
            "AGWACAissw7Go5OBAGQAhgBAkpwASUAAAyAAAFRwo4qCAHmACAissw7Go4qCAI2ACAissw7Go4qCAKGACAissw7Go4qCALWACAissw7Go4qCAMmACAissw7G",
            "o5OBAMgAhgBAkpwASsAAAyAAAFRwo4qCAN2ACAissw7Go4qCAPGACAissw7Go4qCAQWACAissw7Go4qCARmACAissw7Go4qCAS2ACAissw7Go5OBASwAhgBA",
            "kpwAScAAAyAAAFRwo4qCAUGACAissw7Go4qCAVWACAissw7Go4qCAWmACAissw7Go4qCAX2ACAissw7Go4qCAZGACAissw7Go5OBAZAAhgBAkpwASKAAAyAA",
            "AFRwo4qCAaWACAissw7Go4qCAbmACAissw7Go4qCAc2ACAissw7Go4qCAeGACAissw7Go4qCAfWACAissw7Go5OBAfQAhgBAkpwAR4AAAyAAAFRwo4qCAgmA",
            "CAissw7Go4qCAh2ACAissw7Go4qCAjGACAissw7Go4qCAkWACAissw7Go4qCAlmACAissw7Go5OBAlgAhgBAkpwARuAAAyAAAFRwo4qCAm2ACAissw7Go4qC",
            "AoGACAissw7Go4qCApWACAissw7Go4qCAqmACAissw7Go4qCAr2ACAissw7Go5OBArwAhgBAkpwARkAAAyAAAFRwo4qCAtGACAissw7Go4qCAuWACAissw7G",
            "o4qCAvmACAissw7Go4qCAw2ACAissw7Go4qCAyGACAissw7Go5OBAyAAhgBAkpwARcAAAyAAAFRwo4qCAzWACAissw7Go4qCA0mACAissw7Go4qCA12ACAis",
            "sw7Go4qCA3GACAissw7Go4qCA4WACAissw7Go5OBA4QAhgBAkpwARUAAAyAAAFRwo4qCA5mACAissw7Go4qCA62ACAissw7Go4qCA8GACAissw7Go4qCA9WA",
            "CAissw7Go4qCA+mACAissw7Go66BA+iAgkmDQgAD8AI2ADgkHBhCAAAwYAAAXkf//5qZgf////+xTAv////jpIAAo4qCA/2ACAissw7Go4qCBBGACAissw7G",
            "o4qCBCWACAissw7Go4qCBDmACAissw7Go4qCBE2ACAissw7Go5OBBEwAhgBAkpwAROAAAyAAAFRwo4qCBGGACAissw7Go4qCBHWACAissw7Go4qCBImACAis",
            "sw7Go4qCBJ2ACAissw7Go4qCBLGACAissw7Go5OBBLAAhgBAkpwARGAAAyAAAFRwo4qCBMWACAissw7Go4qCBNmACAissw7Go4qCBO2ACAissw7Go4qCBQGA",
            "CAissw7Go4qCBRWACAissw7Go5OBBRQAhgBAkpwARAAAAyAAAFRwo4qCBSmACAissw7Go4qCBT2ACAissw7Go4qCBVGACAissw7Go4qCBWWACAissw7Go4qC",
            "BXmACAissw7Go5OBBXgAhgBAkpwAQ6AAAyAAAFRwo4qCBY2ACAissw7Go4qCBaGACAissw7Go4qCBbWACAissw7Go4qCBcmACAissw7Go4qCBd2ACAissw7G",
            "o5OBBdwAhgBAkpwAQ0AAAyAAAFRwo4qCBfGACAissw7Go4qCBgWACAissw7Go4qCBhmACAissw7Go4qCBi2ACAissw7Go4qCBkGACAissw7Go5OBBkAAhgBA",
            "kpwAQwAAAyAAAFRwo4qCBlWACAissw7Go4qCBmmACAissw7Go4qCBn2ACAissw7Go4qCBpGACAissw7Go4qCBqWACAissw7Go5OBBqQAhgBAkpwAQsAAAyAA",
            "AFRwo4qCBrmACAissw7Go4qCBs2ACAissw7Go4qCBuGACAissw7Go4qCBvWACAissw7Go4qCBwmACAissw7Go5OBBwgAhgBAkpwAQoAAAyAAAFRwo4qCBx2A",
            "CAissw7Go4qCBzGACAissw7Go4qCB0WACAissw7Go4qCB1mACAissw7Go4qCB22ACAissw7Go5OBB2wAhgBAkpwAQkAAAyAAAFRwo4qCB4GACAissw7Go4qC",
            "B5WACAissw7Go4qCB6mACAissw7Go4qCB72ACAissw7Go4qCB9GACAissw7Go4qCB+WACAissw7Go4qCB/mACAissw7Go4qCCA2ACAissw7Go4qCCCGACAis",
            "sw7Go4qCCDWACAissw7Go4qCCEmACAissw7Go4qCCF2ACAissw7Go4qCCHGACAissw7Go4qCCIWACAissw7Go4qCCJmACAissw7Go4qCCK2ACAissw7Go4qC",
            "CMGACAissw7Go4qCCNWACAissw7Go4qCCOmACAissw7Go4qCCP2ACAissw7Go4qCCRGACAissw7Go4qCCSWACAissw7Go4qCCTmACAissw7Go4qCCU2ACAis",
            "sw7Go4qCCWGACAissw7Go4qCCXWACAissw7Go4qCCYmACAissw7Go4qCCZ2ACAissw7Go4qCCbGACAissw7Go4qCCcWACAissw7Go4qCCdmACAissw7Go4qC",
            "Ce2ACAissw7Go4qCCgGACAissw7Go4qCChWACAissw7Go4qCCimACAissw7Go4qCCj2ACAissw7Go4qCClGACAissw7Go4qCCmWACAissw7Go4qCCnmACAis",
            "sw7Go4qCCo2ACAissw7Go4qCCqGACAissw7Go4qCCrWACAissw7Go4qCCsmACAissw7Go4qCCt2ACAissw7Go4qCCvGACAissw7Go4qCCwWACAissw7Go4qC",
            "CxmACAissw7Go4qCCy2ACAissw7Go4qCC0GACAissw7Go4qCC1WACAissw7Go4qCC2mACAissw7Go4qCC32ACAissw7Go4qCC5GACAissw7Go4qCC6WACAis",
            "sw7Go4qCC7mACAissw7Go4qCC82ACAissw7Go4qCC+GACAissw7Go4qCC/WACAissw7Go4qCDAmACAissw7Go4qCDB2ACAissw7Go4qCDDGACAissw7Go4qC",
            "DEWACAissw7Go4qCDFmACAissw7Go4qCDG2ACAissw7Go4qCDIGACAissw7Go4qCDJWACAissw7Go4qCDKmACAissw7Go4qCDL2ACAissw7Go4qCDNGACAis",
            "sw7Go4qCDOWACAissw7Go4qCDPmACAissw7Go4qCDQ2ACAissw7Go4qCDSGACAissw7Go4qCDTWACAissw7Go4qCDUmACAissw7Go4qCDV2ACAissw7Go4qC",
            "DXGACAissw7Go4qCDYWACAissw7Go4qCDZmACAissw7Go4qCDa2ACAissw7Go4qCDcGACAissw7Go4qCDdWACAissw7Go4qCDemACAissw7Go4qCDf2ACAis",
            "sw7Go4qCDhGACAissw7Go4qCDiWACAissw7Go4qCDjmACAissw7Go4qCDk2ACAissw7Go4qCDmGACAissw7Go4qCDnWACAissw7Go4qCDomACAissw7Go4qC",
            "Dp2ACAissw7Go4qCDrGACAissw7Go4qCDsWACAissw7Go4qCDtmACAissw7Go4qCDu2ACAissw7Go4qCDwGACAissw7Go4qCDxWACAissw7Go4qCDymACAis",
            "sw7Go4qCDz2ACAissw7Go4qCD1GACAissw7Go4qCD2WACAissw7Go4qCD3mACAissw7Go4qCD42ACAissw7Go4qCD6GACAissw7Go4qCD7WACAissw7Go4qC",
            "D8mACAissw7Go4qCD92ACAissw7Go4qCD/GACAissw7Go4qCEAWACAissw7Go4qCEBmACAissw7Go4qCEC2ACAissw7Go4qCEEGACAissw7Go4qCEFWACAis",
            "sw7Go4qCEGmACAissw7Go4qCEH2ACAissw7Go4qCEJGACAissw7Go4qCEKWACAissw7Go4qCELmACAissw7Go4qCEM2ACAissw7Go4qCEOGACAissw7Go4qC",
            "EPWACAissw7Go4qCEQmACAissw7Go4qCER2ACAissw7Go4qCETGACAissw7Go4qCEUWACAissw7Go4qCEVmACAissw7Go4qCEW2ACAissw7Go4qCEYGACAis",
            "sw7Go4qCEZWACAissw7Go4qCEamACAissw7Go4qCEb2ACAissw7Go4qCEdGACAissw7Go4qCEeWACAissw7Go4qCEfmACAissw7Go4qCEg2ACAissw7Go4qC",
            "EiGACAissw7Go4qCEjWACAissw7Go4qCEkmACAissw7Go4qCEl2ACAissw7Go4qCEnGACAissw7Go4qCEoWACAissw7Go4qCEpmACAissw7Go4qCEq2ACAis",
            "sw7Go4qCEsGACAissw7Go4qCEtWACAissw7Go4qCEumACAissw7Go4qCEv2ACAissw7Go4qCExGACAissw7Go4qCEyWACAissw7Go4qCEzmACAissw7Go4qC",
            "E02ACAissw7Go4qCE2GACAissw7GH0O2dUu854ITdaOKggAAgAgIrLMOxqOKggAUgAgIrLMOxqOKggAogAgIrLMOxqOKggA8gAgIrLMOxqOKggBQgAgIrLMO",
            "xqOKggBkgAgIrLMOxqOKggB4gAgIrLMOxqOKggCMgAgIrLMOxqOKggCggAgIrLMOxqOKggC0gAgIrLMOxqOKggDIgAgIrLMOxqOKggDcgAgIrLMOxqOKggDw",
            "gAgIrLMOxqOKggEEgAgIrLMOxqOKggEYgAgIrLMOxqOKggEsgAgIrLMOxqOKggFAgAgIrLMOxqOKggFUgAgIrLMOxqOKggFogAgIrLMOxqOKggF8gAgIrLMO",
            "xqOKggGQgAgIrLMOxqOKggGkgAgIrLMOxqOKggG4gAgIrLMOxqOKggHMgAgIrLMOxqOKggHggAgIrLMOxqOKggH0gAgIrLMOxqOKggIIgAgIrLMOxqOKggIc",
            "gAgIrLMOxqOKggIwgAgIrLMOxqOKggJEgAgIrLMOxqOKggJYgAgIrLMOxqOKggJsgAgIrLMOxqOKggKAgAgIrLMOxqOKggKUgAgIrLMOxqOKggKogAgIrLMO",
            "xqOKggK8gAgIrLMOxqOKggLQgAgIrLMOxqOKggLkgAgIrLMOxqOKggL4gAgIrLMOxqOKggMMgAgIrLMOxqOKggMggAgIrLMOxqOKggM0gAgIrLMOxqOKggNI",
            "gAgIrLMOxqOKggNcgAgIrLMOxqOKggNwgAgIrLMOxqOKggOEgAgIrLMOxqOKggOYgAgIrLMOxqOKggOsgAgIrLMOxqOKggPAgAgIrLMOxqOKggPUgAgIrLMO",
            "xqOKggPogAgIrLMOxqOKggP8gAgIrLMOxqOKggQQgAgIrLMOxqOKggQkgAgIrLMOxqOKggQ4gAgIrLMOxqOKggRMgAgIrLMOxqOKggRggAgIrLMOxqOKggR0",
            "gAgIrLMOxqOKggSIgAgIrLMOxqOKggScgAgIrLMOxqOKggSwgAgIrLMOxqOKggTEgAgIrLMOxqOKggTYgAgIrLMOxqOKggTsgAgIrLMOxqOKggUAgAgIrLMO",
            "xqOKggUUgAgIrLMOxqOKggUogAgIrLMOxqOKggU8gAgIrLMOxqOKggVQgAgIrLMOxqOKggVkgAgIrLMOxqOKggV4gAgIrLMOxqOKggWMgAgIrLMOxqOKggWg",
            "gAgIrLMOxqOKggW0gAgIrLMOxqOKggXIgAgIrLMOxqOKggXcgAgIrLMOxqOKggXwgAgIrLMOxqOKggYEgAgIrLMOxqOKggYYgAgIrLMOxqOKggYsgAgIrLMO",
            "xqOKggZAgAgIrLMOxqOKggZUgAgIrLMOxqOKggZogAgIrLMOxqOKggZ8gAgIrLMOxqOKggaQgAgIrLMOxqOKggakgAgIrLMOxqOKgga4gAgIrLMOxqOKggbM",
            "gAgIrLMOxqOKggbggAgIrLMOxqOKggb0gAgIrLMOxqOKggcIgAgIrLMOxqOKggccgAgIrLMOxqOKggcwgAgIrLMOxqOKggdEgAgIrLMOxqOKggdYgAgIrLMO",
            "xqOKggdsgAgIrLMOxqOKggeAgAgIrLMOxqOKggeUgAgIrLMOxqOKggeogAgIrLMOxqOKgge8gAgIrLMOxqOKggfQgAgIrLMOxqOKggfkgAgIrLMOxqOKggf4",
            "gAgIrLMOxqOKgggMgAgIrLMOxqOKgggggAgIrLMOxqOKggg0gAgIrLMOxqOKgghIgAgIrLMOxqOKgghcgAgIrLMOxqOKgghwgAgIrLMOxqOKggiEgAgIrLMO",
            "xqOKggiYgAgIrLMOxqOKggisgAgIrLMOxqOKggjAgAgIrLMOxqOKggjUgAgIrLMOxqOKggjogAgIrLMOxqOKggj8gAgIrLMOxqOKggkQgAgIrLMOxqOKggkk",
            "gAgIrLMOxqOKggk4gAgIrLMOxqOKgglMgAgIrLMOxqOKgglggAgIrLMOxqOKggl0gAgIrLMOxqOKggmIgAgIrLMOxqOKggmcgAgIrLMOxqOKggmwgAgIrLMO",
            "xqOKggnEgAgIrLMOxqOKggnYgAgIrLMOxqOKggnsgAgIrLMOxqOKggoAgAgIrLMOxqOKggoUgAgIrLMOxqOKggoogAgIrLMOxqOKggo8gAgIrLMOxqOKggpQ",
            "gAgIrLMOxqOKggpkgAgIrLMOxqOKggp4gAgIrLMOxqOKggqMgAgIrLMOxqOKggqggAgIrLMOxqOKggq0gAgIrLMOxqOKggrIgAgIrLMOxqOKggrcgAgIrLMO",
            "xqOKggrwgAgIrLMOxqOKggsEgAgIrLMOxqOKggsYgAgIrLMOxqOKggssgAgIrLMOxqOKggtAgAgIrLMOxqOKggtUgAgIrLMOxqOKggtogAgIrLMOxqOKggt8",
            "gAgIrLMOxqOKgguQgAgIrLMOxqOKggukgAgIrLMOxqOKggu4gAgIrLMOxqOKggvMgAgIrLMOxqOKggvggAgIrLMOxqOKggv0gAgIrLMOxqOKggwIgAgIrLMO",
            "xqOKggwcgAgIrLMOxqOKggwwgAgIrLMOxqOKggxEgAgIrLMOxqOKggxYgAgIrLMOxqOKggxsgAgIrLMOxqOKggyAgAgIrLMOxqOKggyUgAgIrLMOxqOKggyo",
            "gAgIrLMOxqOKggy8gAgIrLMOxqOKggzQgAgIrLMOxqOKggzkgAgIrLMOxqOKggz4gAgIrLMOxqOKgg0MgAgIrLMOxqOKgg0ggAgIrLMOxqOKgg00gAgIrLMO",
            "xqOKgg1IgAgIrLMOxqOKgg1cgAgIrLMOxqOKgg1wgAgIrLMOxqOKgg2EgAgIrLMOxqOKgg2YgAgIrLMOxqOKgg2sgAgIrLMOxqOKgg3AgAgIrLMOxqOKgg3U",
            "gAgIrLMOxqOKgg3ogAgIrLMOxqOKgg38gAgIrLMOxqOKgg4QgAgIrLMOxqOKgg4kgAgIrLMOxqOKgg44gAgIrLMOxqOKgg5MgAgIrLMOxqOKgg5ggAgIrLMO",
            "xqOKgg50gAgIrLMOxqOKgg6IgAgIrLMOxqOKgg6cgAgIrLMOxqOKgg6wgAgIrLMOxqOKgg7EgAgIrLMOxqOKgg7YgAgIrLMOxqOKgg7sgAgIrLMOxqOKgg8A",
            "gAgIrLMOxqOKgg8UgAgIrLMOxqOKgg8ogAgIrLMOxqOKgg88gAgIrLMOxqOKgg9QgAgIrLMOxqOKgg9kgAgIrLMOxqOKgg94gAgIrLMOxqOKgg+MgAgIrLMO",
            "xqOKgg+ggAgIrLMOxqOKgg+0gAgIrLMOxqOKgg/IgAgIrLMOxqOKgg/cgAgIrLMOxqOKgg/wgAgIrLMOxqOKghAEgAgIrLMOxqOKghAYgAgIrLMOxqOKghAs",
            "gAgIrLMOxqOKghBAgAgIrLMOxqOKghBUgAgIrLMOxqOKghBogAgIrLMOxqOKghB8gAgIrLMOxqOKghCQgAgIrLMOxqOKghCkgAgIrLMOxqOKghC4gAgIrLMO",
            "xqOKghDMgAgIrLMOxqOKghDggAgIrLMOxqOKghD0gAgIrLMOxqOKghEIgAgIrLMOxqOKghEcgAgIrLMOxqOKghEwgAgIrLMOxqOKghFEgAgIrLMOxqOKghFY",
            "gAgIrLMOxqOKghFsgAgIrLMOxqOKghGAgAgIrLMOxqOKghGUgAgIrLMOxqOKghGogAgIrLMOxqOKghG8gAgIrLMOxqOKghHQgAgIrLMOxqOKghHkgAgIrLMO",
            "xqOKghH4gAgIrLMOxqOKghIMgAgIrLMOxqOKghIggAgIrLMOxqOKghI0gAgIrLMOxqOKghJIgAgIrLMOxqOKghJcgAgIrLMOxqOKghJwgAgIrLMOxqOKghKE",
            "gAgIrLMOxqOKghKYgAgIrLMOxqOKghKsgAgIrLMOxqOKghLAgAgIrLMOxqOKghLUgAgIrLMOxqOKghLogAgIrLMOxqOKghL8gAgIrLMOxqOKghMQgAgIrLMO",
            "xqOKghMkgAgIrLMOxqOKghM4gAgIrLMOxqOKghNMgAgIrLMOxqOKghNggAgIrLMOxqOKghN0gAgIrLMOxh9DtnWo54Im/aOKggAAgAgIrLMOxqCWoYqCABQA",
            "CAissw7Gm4EHdaKEAM3+YBxTu2uku4+zgQC3iveBAfGCAoHwgRC7kbOCA+i3i/eBAfGCAoHwggNV",
        ].joined()

        static func write(to url: URL) throws {
            guard let data = Data(base64Encoded: encoded) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try data.write(to: url, options: .atomic)
        }
    }
#endif
