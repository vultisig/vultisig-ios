//
//  TonKnownRouters.swift
//  VultisigApp
//

import Foundation
import WalletCore

/// Known router/factory addresses used to bind opcode-based swap classification
/// to specific contracts. Without these checks, an attacker could craft a body
/// that decodes as a "swap" and have it labeled as such in the keysign UI
/// even though it is actually a transfer to an attacker-controlled
/// destination — TON message-body opcodes are contract-local, not globally
/// unique.
///
/// Mirrors `knownRouters.ts` in the Vultisig SDK. Refresh procedure documented
/// there; rerun after a STON.fi or DeDust router redeploy.
enum TonKnownRouters {

    static let stonfiV2Routers: Set<String> = normalize([
        "EQABT9GCyDI60CbC4c6uS33HFDwaqd6MddiwIIw7CXTgNR3A",
        "EQACn16m9OrZ-mw186M4NlIpVP8Tb3q6SV9aX8NjSgVfJTo9",
        "EQADEFMTMnC-gu5v2U0ZY8AYaGhAOk9TcECg1TOquAW3r-IE",
        "EQAGV9vw11tKW2QOCYCXEmIdyufM3p5CfcgHcY9NiiBLfZGH",
        "EQAJG5pyZPWEiQiMVJdf7bDRgRLzg6QR57qKeRsOrMO-ncZN",
        "EQAQYbnb1EGK0Wb8mk3vEW4vbHTyv7cOcfJlPWQ87_6_qfzR",
        "EQATvO_BXfkFocOXhlve01EZfsiyFjoV-0k9CLmpgwtzVtcN",
        "EQAgERF5tvrNn0AM2Rrrvk-MutGP60ZL70bJPuqvCTGY-17_",
        "EQAiLV677BgHNXEUuDJ3Cw8K5WOiJSO86xh8YQq2LthJEoED",
        "EQAiv3IuxYA6ZGEunOgZSTuMBzbpjwRbWw09-WsE-iqKKMrK",
        "EQAyD7O8CvVdR8AEJcr96fHI1ifFq21S8QMt1czi5IfJPyfA",
        "EQAyY2lBQ6RsVe88CKTmeH3BWWsUCWu7ugQNaf5kwLDYAoKt",
        "EQAz1D0ZUiG_9XCyjrJ1-xTx-CnmnQ3J3LMKQ7sZTr-XlNZP",
        "EQBCl1JANkTpMpJ9N3lZktPMpp2btRe2vVwHon0la8ibRied",
        "EQBCtlN7Zy96qx-3yH0Yi4V0SNtQ-8RbhYaNs65MC4Hwfq31",
        "EQBQErJi0DHgKYseIHtrQk4N5CQLCr3XYwkQIEw0HNs470OG",
        "EQBQ_UBQvR9ryUjKDwijtoiyyga2Wl-yJm6Y8gl0k-HDh_5x",
        "EQBSNX_5mSikBVttWhIaIb0f8jJU7fL6kvyyFVppd7dWRO6M",
        "EQBZj7nhXNhB4O9rRCn4qGS82DZaPUPlyM2k6ZrbvQ1j3Ge7",
        "EQBigMnbY4NU1uwdvzertV5mv_yI7282R-ffW7XZFWPEVRDG",
        "EQBjK_kjY5R_DoyTRff109VzFrSlKFCC_gOOWIMtyEvCcv2J",
        "EQBjM7B2PKa82IPKrUFbMFaKeQDFGTMRnrvY1TmptC7Kxz7B",
        "EQBqgCTdrtSod76UrcOeALSiLCp3WuNIFQBQvyjjlQMvwLkc",
        "EQBwpBGEAb-NgjUxpmARAgVl8C4F_5GsXxZ3dpsA1qzQerNl",
        "EQByADL5Ra2dldrMSBctgfSm2X2W1P61NVW2RYDb8eJNJGx6",
        "EQBzkqAN4ViYdS24lD2fFPe8odHn2rUkfMYbEJ88EBKBAS1b",
        "EQC67o2-2UzR1cJFrUGL5M7OAnLgG8oY_tHaTgGmR63LQNV-",
        "EQCCdNmj4QbNjrg_PM-JJE-B9f_czXLkYmrO7P9UkA6tt95m",
        "EQCDT9dCT52pdfsLNW0e6qP5T3cgq7M4Ug72zkGYgP17tsWD",
        "EQCRgwuFbPRR7TGodkJwbjiBtNtb0hfzJIliV-5kY6lKr_18",
        "EQCS4UEa5UaJLzOyyKieqQOQ2P9M-7kXpkO5HnP3Bv250cN3",
        "EQChoROpuUM4cpN6IRzqNTrkP9iVZHYoHgxMABDVU28vlUiG",
        "EQCiypoBWNIEPlarBp04UePyEj5zH0ZDHxuRNqJ1WQx3FCY-",
        "EQCiz74FCV2lYlvFPEYhL3Jql8WwIO7QvbvYT-LQH0SmtCgI",
        "EQCpuYtq55nhkwYDmL4OWjsrdYy83gj5_49nNRQ5CrPOze49",
        "EQCx0HDJ_DxLxDSQyfsEqHI8Rs65nygvdmeD9Ra7rY15OWN8",
        "EQCxkYVQcfXKw9uJ-MMtutvR2Cu0DVCZFfLNBp6NwXgO8vQY",
        "EQD11suHkrO_1Mb5IIdYFx5ZPy38MuHoeHx6dA-QRaD8w0UJ",
        "EQDAPye7HAPAAl4WXpz5jOCdhf2H9h9QkkzRQ-6K5usiuQeC",
        "EQDBYUj5KEPUQrbj7da742UYJIeT9QU5C2dKsi12SdQ3yh9a",
        "EQDQ6j53q21HuZtw6oclm7z4LU2cG6S2OKvpSSMH548d7kJT",
        "EQDTb1w1TCohFqnNcyPrrbbBJQdAwwPn8DbCoaSUd0S5T4fB",
        "EQDgebEMA6yriI7SMffE65DIVA9rzSRmfGV_gy3ylIhLicY8",
        "EQDh5oHPvfRwPu2bORBGCoLEO4WQZKL4fk5DD1gydeNG9oEH",
        "EQDi1eWU3HWWst8owY8OMq2Dz9nJJEHUROza8R-_wEGb8yu6",
        "EQDkncuJ267Py3EmL2XAN7YsSNQMUu8u-GHsW9jVljcH8fr5",
        "EQDwyjgjnTXJVPjXji3OPtUilcCjceGVQOLGwr9_sRLjImfG",
        "EQDx--jUU9PUtHltPYZX7wdzIi0SPY3KZ8nvOs0iZvQJd6Ql"
    ])

    static let stonfiV2PtonWallets: Set<String> = normalize([
        "EQA2O81nzig4IUsCp_8dpzglywsCx-1ESPFzl0ygs1hFYUa2",
        "EQACuz151snlY46PKdUOkyiCf0zzcxMsN6XmKQkSKZjkvyFH",
        "EQAD2AcAb4blnbeGPPugZoxSpeibAMTB5kyDMIpUgKrsqk-z",
        "EQADMtjROtxVRcr1PZ8Zoq6Uxv-5O6uRw7v2XktW0WRtZDnK",
        "EQAGM0cbPP-HmOONE_RBFnPtHJDkY5qZ_crocAns0QW25e8p",
        "EQAIuYlddISZbBf7iymZ-WPP9zHaVj9Kg45OH-PgntVz9QbQ",
        "EQAKz7pQ4mi88Br4WKWcRozQbuRP3xi3eNnwlKa12ECcPfZG",
        "EQARZ1hF4v95ELsH7pCPMN79_UeqKOOgOjt8xrkW9HhIM-u1",
        "EQARs8oCeUBx5sWfazL6gZzTFAA9-RgnicsGhHBA8tDLIXgS",
        "EQAg3Rfrs5JAy31xPIv0hVsAkjDmF8yTxxxkygNvpzNBcJAB",
        "EQAgXtyQlqVF2V3F4mKlbvYzUijlGjUmJbPWkWuiFNdpzWL_",
        "EQAmV2BzRi6c-S1263Ar9HhyCLrvtMEae_qfEzhxnK7qSpr0",
        "EQAyEwoQcmDv0385t9szG-XIUcWMpYlUAOpA5I4HAViY-FnW",
        "EQAyvcnP0RexLvnsQMXfKYnk18Bzl3Y-iGt6bXqFB75ugXmE",
        "EQBB_dTiG6u4IIbDT80yirqwmLpwRp7cDGkdrmvQ3Xs_39xM",
        "EQBDOw08nLEwr9TTXyXDiPuBogHZM_1Rk42Ks8h-FQkP330_",
        "EQBS0OA18gacX-knOwi7kYuZms3JFwSs4A6j3DvowxfCX9aC",
        "EQBSDTCjmP35i5CnqT0IiankTmJeOBnUzq7eJ19oO6JgOPgs",
        "EQBTYCx7TGgVgaIr3tuJ3r_91E6FUBBWLtT73lTYYmrIc5gb",
        "EQBiLHuQjDj4fNyCD7Ch5HwpNGldlb5g-LMwQ1kStQ4NM5kv",
        "EQBicl-T79f0FwI_nygtAm_ISq15BVusRKEbZnC2_2QFjH34",
        "EQBiy9ltu3lkML1i_MAVW2yaXOsPeJ3NXCXQLlcAx-6lKrN1",
        "EQBvwdaM2LT9JPZGYdqYMCtIuLzjjAqHDSdaJW8fErAU7JUM",
        "EQBwU5CgFHiNsGKIBetAsMqnoDCtEQIcC3m8HW12GGDz6KfN",
        "EQByjaOja6-prxDrniGIzs-lBmNnP-nsvGxH1X2y4M3M5sjm",
        "EQBzIe_KYGrezmSS3ua9buM0P8vzEnMFDrsv1prFnwP43hFk",
        "EQC4V6MEH2RGiHw5a9g74AXEjyPR1qA-N9mzMEIs9hOSZzVP",
        "EQCCcuEVMGOSBQwv8Wmak1zbB8WpIuQbfavZYc3cL3QPNlK7",
        "EQCCgTcJEugMCmQjJDJLTFlu56od9fJDfkTSNv4QEGpHihJx",
        "EQCSIMGBps_qzRG3uPYhON8bucyCtu0mYdL1-u4gSz77IBa3",
        "EQCSQy327bW5cik1IycFmY4Qvsmgt-o4F6Ze54-lv2AOPBSk",
        "EQCcM8n2_K5D9Gu-YkyxM2W35WFs7ekYSbV9lgjXUDYofYt4",
        "EQCh82fvi6mY0FdoKprvfDLE2q-nE9FIU3SWTVLgNqMJliOO",
        "EQChdJmlvKnQVkiOwUYnUKJU_zgoyLT81XIyYxVH6RO8OtlH",
        "EQCjEo7QNUH5S2tVjYgFFdEh1pherydH9K-nrHx0aScsq7U5",
        "EQClcxRtn7nhZ3zzwsLk_itGaSe0r1r0Dj8fBLAxonkKNsZh",
        "EQCyfHYh17xx-KwZvcc1t61tLVVCxSk0jYxwRznbpHqQ-R0k",
        "EQCzUiz7TFS7p7ByYXt-c3lJDmyGvmHTQIm0vhwSiiiaLpVj",
        "EQD-zKpOa1GjFQDOMnP4A-tX3ntmgV7vs127m0tS_SrJY3kG",
        "EQDARm-e3yRFmxAabT5OfXKjFp23PS6p7hXBwwrgmvkdbXCr",
        "EQDBXpJBctAKlbAMWqH2iTPyBPfdBPeQZ6CGRp1oKBqQkEDL",
        "EQDTN22aBi-Pa_GyDWi8wBuVUxLhOwfAklgN5-bbTk87-uBh",
        "EQDTx6o7gmGo8cuJt_3EHEgO1RmGnLtGTzgTOsG5pAYs0uYd",
        "EQDgXEo6f94Bq90eHGFTVK0LyhGaePDhXEgiv1JK6LHFEYRP",
        "EQDiolbUI-wbmncBen7bYEG1pK_F27RKlqoRWCzSSA8mpqfe",
        "EQDix2qMOc-QO05Nn9X7oKFnYTb3bvtxN7ySmzoGljrFv2bX",
        "EQDwOyDlewGw8MkeXgZ_oOmPTIhJIlaJwhJmf4ffIPKv-294",
        "EQDwVbvZWrXEWQ_lL_69WehyNkNKm4pkswOSeJQtzx1gcHMF"
    ])

    /// DeDust mainnet TON Native Vault — the contract that receives the
    /// `swap#ea06185d` op for native-TON-in swaps. NOT the factory: the
    /// factory only handles `create_vault` / `create_pool`. The native
    /// vault is a singleton on mainnet.
    static let dedustNativeVaults: Set<String> = normalize([
        "EQDa4VOnTYlLvDJ0gZjNYm5PXfSmmtL6Vs6A_CZEtXCNICq_"
    ])

    /// Normalise each address to user-friendly bounceable form so URL-safe
    /// and raw variants of the same address compare as equal. Unparseable
    /// entries are dropped (and would be developer error, not user input).
    private static func normalize(_ addresses: [String]) -> Set<String> {
        Set(addresses.compactMap {
            TONAddressConverter.toUserFriendly(address: $0, bounceable: true, testnet: false)
        })
    }
}
