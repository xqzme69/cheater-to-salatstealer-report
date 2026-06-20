rule Windows_Trojan_SalatStealer_CheaterTo_WebRat_Jun2026
{
    meta:
        description = "Campaign-specific detection for the cheater.to SalatStealer/WebRat unpacked Go payload"
        author = "xqzme"
        date = "2026-06-20"
        reference = "https://github.com/xqzme69/cheater-to-salatstealer-report"
        sample_sha256 = "D8ED4BA2515A7867F6650B9A128A464E92765549201BFE94715967A843B906D5"
        scope = "file"

    strings:
        $net_01 = "main.getEp" ascii
        $net_02 = "main.getBC" ascii
        $net_03 = "main.initConnection" ascii
        $net_04 = "main.changeEndpoint" ascii
        $net_05 = "main.tryTonResolve" ascii
        $net_06 = "main.tonResolve" ascii

        $steal_01 = "main.Steal" ascii
        $steal_02 = "main.getChromeLogins" ascii
        $steal_03 = "main.getChromeCookies" ascii
        $steal_04 = "main.getGeckoLogins" ascii
        $steal_05 = "main.getDiscord" ascii
        $steal_06 = "main.getSteams" ascii
        $steal_07 = "main.runKeylogger" ascii

        $rat_01 = "main.screenStream" ascii
        $rat_02 = "main.downloadFile" ascii
        $rat_03 = "main.executeCommand" ascii
        $rat_04 = "main.shellCommand" ascii
        $rat_05 = "main.staticinstall" ascii
        $rat_06 = "main.newTask" ascii
        $rat_07 = "main.selfDelete" ascii

        $path_01 = "Clients\\DiscordTokens.txt" ascii
        $path_02 = "Clients\\SteamTokens.txt" ascii
        $path_03 = "SOFTWARE\\Valve\\Steam" ascii
        $path_04 = "loginusers.vdf" ascii

        // Encrypted C2 blob prefixes decoded in the write-up as salator.es/sa1at/,
        // wruser.org/sa1at/ and wruser.org:992/sa1at/.
        $c2_blob_01 = { A5 A7 A5 A5 D8 0D 90 F2 91 DE 6B 85 93 46 C7 C9 D3 05 66 D0 87 60 C1 3B 1A 60 41 01 FF 6D 81 EF }
        $c2_blob_02 = { A5 A7 A5 A5 01 48 5E D5 73 BC 33 60 D5 37 B5 57 20 86 C9 EE 9D 65 2B 87 54 26 0C BE 15 7C F6 06 }
        $c2_blob_03 = { A5 A7 A5 A5 86 B1 7E AF D1 EA 13 C3 E8 46 99 CA A3 DC A9 12 9A 72 2F EB 60 E4 B6 8B 64 F0 5E 84 }

    condition:
        uint16(0) == 0x5A4D and
        filesize < 20MB and
        (
            (5 of ($net_*) and 5 of ($steal_*) and 3 of ($rat_*)) or
            (4 of ($net_*) and 4 of ($steal_*) and any of ($c2_blob_*)) or
            (4 of ($net_*) and 3 of ($steal_*) and 2 of ($path_*) and any of ($c2_blob_*))
        )
}
