//
//  KaminoTransactionFixtures.swift
//  VultisigAppTests
//
//  Golden vectors captured from `api.kamino.finance` on 2026-08-04, plus the
//  contents of the address lookup tables they reference, read from mainnet the
//  same day.
//
//  The `injected` payloads are not expectations invented here: each was produced
//  by the reference implementation before any Swift was written, and each was
//  simulated on mainnet through `simulateTransaction` with `err: null` and the
//  ComputeBudget program visible in the logs. So a Swift result that differs from
//  one of these is wrong about a transaction that is known to execute.
//

import Foundation
@testable import VultisigApp

enum KaminoTransactionFixtures {

    /// Every vector was injected at this price, in micro-lamports per compute
    /// unit.
    static let unitPriceMicroLamports: UInt64 = 20_000

    struct Vector {
        let name: String
        /// The transaction exactly as the Kamino API returned it.
        let source: String
        /// The same transaction with the two ComputeBudget instructions injected.
        let injected: String
        let unitLimit: UInt32
        let feePayer: String
        let lookupTable: String

        /// `injected`, plus the attribution memo the preparer appends last —
        /// i.e. the exact bytes the app now hands to keysign.
        ///
        /// DERIVED rather than pasted, on purpose. `injected` is the artifact
        /// that was produced by the reference implementation and simulated on
        /// mainnet; the memo is a byte edit whose exactness is proven on its own
        /// in `SolanaV0TransactionTests`. A second frozen base64 blob here would
        /// have no provenance of its own — it could only be this same edit,
        /// recorded — so it would assert the edit against itself and pin nothing.
        var tagged: String {
            get throws {
                try SolanaV0Transaction(base64Transaction: injected)
                    .injectingMemo(KaminoAttribution.memoTag)
                    .base64EncodedTransaction
            }
        }
    }

    static let usdcDeposit = Vector(
        name: "Steakhouse USDC deposit",
        source: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAFCX6M\
            CIdgv94d3c8ywX8gm4JC7lKq8TH6zYjQ6ixtCwbyi2G+J7TtwhmmIGAksFHWHBRuD3RE+zBbFhbNlyaHUS/T6oz1rKyozQUg\
            dRIXXEPO9Upd2Z7eIKFrVSU3OPOX3AwoNIw0S/83XKQnpefdOo4z5yPOpkC2dDdTPAbIHsm7AAAAAAAAAAAAAAAAAAAAAAAA\
            AAAAAAAAAAAAAAAAAAAP2mzp9mGY3YcNiphvMGdcRvg+L1KDSHlS9dUFY+PveoyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASO\
            e9jb6fhZ2LAQF2PT5R8SbmFW3oXejGEwWbhEaNDaP+iioiUcxwEE2Qrx24k57DX/lNlkDVfcwyeUuz4btm/TroSahNzblN76\
            Ws6qir7XRG1XkeCtBuHFqihTJrTDGrQlDXGSFqA+BAYGAAMACQQaAQEIFQARDRYUCQIDGBoaBQgQDwoMFRMXEhDyI8aJUuHy\
            toCWmAAAAAAABwgAAAAAAQsEGQhvEbn6PHom/gcIAAELDgMJBxoQzrDKEsjRs2z//////////wGC6dRmw0Z9LrKw2cy+tHvb\
            9JXuHBu0d9Dar60DX6fr5AkFNTElLzITCQEJJxUECwI3BwYD
            """,
        injected: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAGCn6M\
            CIdgv94d3c8ywX8gm4JC7lKq8TH6zYjQ6ixtCwbyi2G+J7TtwhmmIGAksFHWHBRuD3RE+zBbFhbNlyaHUS/T6oz1rKyozQUg\
            dRIXXEPO9Upd2Z7eIKFrVSU3OPOX3AwoNIw0S/83XKQnpefdOo4z5yPOpkC2dDdTPAbIHsm7AAAAAAAAAAAAAAAAAAAAAAAA\
            AAAAAAAAAAAAAAAAAAAP2mzp9mGY3YcNiphvMGdcRvg+L1KDSHlS9dUFY+PveoyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASO\
            e9jb6fhZ2LAQF2PT5R8SbmFW3oXejGEwWbhEaNDaP+iioiUcxwEE2Qrx24k57DX/lNlkDVfcwyeUuz4btm/TroSahNzblAMG\
            Rm/lIRcy/+ytunLDm+e8jOW7xfcSayxDmzpAAAAA3vpazqqKvtdEbVeR4K0G4cWqKFMmtMMatCUNcZIWoD4GCQAFAgDiBAAJ\
            AAkDIE4AAAAAAAAGBgADAAoEGwEBCBUAEg4XFQoCAxkbGwUIERALDRYUGBMQ8iPGiVLh8raAlpgAAAAAAAcIAAAAAAEMBBoI\
            bxG5+jx6Jv4HCAABDA8DCgcbEM6wyhLI0bNs//////////8BgunUZsNGfS6ysNnMvrR72/SV7hwbtHfQ2q+tA1+n6+QJBTUx\
            JS8yEwkBCScVBAsCNwcGAw==
            """,
        unitLimit: 320000,
        feePayer: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
        lookupTable: "9p2oT9J6BojHigd3V5qXzrwsQf4dtgMgLxtrzLVR3rwu"
    )

    static let solDeposit = Vector(
        name: "Allez SOL deposit",
        source: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAGDH6M\
            CIdgv94d3c8ywX8gm4JC7lKq8TH6zYjQ6ixtCwbyJnd9pKyNWm8rX5WMWlaRpEuaYsAMd/0uKk2HNuILqFNNvPvC4A7dhX1Z\
            Jyo29DiuibPP/uANSC1jj19qJzEK31tWVuPJV5ITcuOIn1fHs4hHodajEBxE75fcJD2QevvWbQ/ffN89KMzS1moKr3xD+eaL\
            jFLD93Uu7/6fCChoRW/6HoLYlf5IbdNEuFQby9p5byRMsWwK5OpCzyixXzveqAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
            AAAAAAAAD9ps6fZhmN2HDYqYbzBnXEb4Pi9Sg0h5UvXVBWPj73qMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4Wdiw\
            EBdj0+UfEm5hVt6F3oxhMFm4RGjQ2j/ooqIlHMcBBNkK8duJOew1/5TZZA1X3MMnlLs+G7Zv066EmoTc25QG3fbh12Whk9nL\
            4UbO63msHLSF7V9bN5E6jPWFfv8AqQratdTZskh3RX3JYgwHZm2POqig2u19lkObE1kyFxBnBwgGAAQAHQYLAQEGAgAEDAIA\
            AAAAZc0dAAAAAAsBBAERCAYAAwASBgsBAQoZAA8FHRYSBAMcCwsHCg4QDRQRDBsVFxgaGRDyI8aJUuHytgBlzR0AAAAACQgA\
            AAAAAhMGHghvEbn6PHom/gkIAAITAQMSCQsQzrDKEsjRs2z//////////wFcvAkvUgYmlpRjmt1MX98IzA/9elzQ9ld+Vs/y\
            AHeYyAlbGwkBEjwFUDEKFAQdM0g+CwcCBg==
            """,
        injected: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAHDX6M\
            CIdgv94d3c8ywX8gm4JC7lKq8TH6zYjQ6ixtCwbyJnd9pKyNWm8rX5WMWlaRpEuaYsAMd/0uKk2HNuILqFNNvPvC4A7dhX1Z\
            Jyo29DiuibPP/uANSC1jj19qJzEK31tWVuPJV5ITcuOIn1fHs4hHodajEBxE75fcJD2QevvWbQ/ffN89KMzS1moKr3xD+eaL\
            jFLD93Uu7/6fCChoRW/6HoLYlf5IbdNEuFQby9p5byRMsWwK5OpCzyixXzveqAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
            AAAAAAAAD9ps6fZhmN2HDYqYbzBnXEb4Pi9Sg0h5UvXVBWPj73qMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4Wdiw\
            EBdj0+UfEm5hVt6F3oxhMFm4RGjQ2j/ooqIlHMcBBNkK8duJOew1/5TZZA1X3MMnlLs+G7Zv066EmoTc25QG3fbh12Whk9nL\
            4UbO63msHLSF7V9bN5E6jPWFfv8AqQMGRm/lIRcy/+ytunLDm+e8jOW7xfcSayxDmzpAAAAACtq11NmySHdFfcliDAdmbY86\
            qKDa7X2WQ5sTWTIXEGcJDAAFAjBXBQAMAAkDIE4AAAAAAAAIBgAEAB4GCwEBBgIABAwCAAAAAGXNHQAAAAALAQQBEQgGAAMA\
            EwYLAQEKGQAQBR4XEwQDHQsLBwoPEQ4VEg0cFhgZGxoQ8iPGiVLh8rYAZc0dAAAAAAkIAAAAAAIUBh8IbxG5+jx6Jv4JCAAC\
            FAEDEwkLEM6wyhLI0bNs//////////8BXLwJL1IGJpaUY5rdTF/fCMwP/Xpc0PZXflbP8gB3mMgJWxsJARI8BVAxChQEHTNI\
            PgsHAgY=
            """,
        unitLimit: 350000,
        feePayer: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
        lookupTable: "7EzosNioQ6FDNvMKLfg6om5wTVHiJo9vVx7DZNGYBKU3"
    )

    static let usdcWithdraw = Vector(
        name: "Steakhouse USDC withdraw",
        source: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAFCKsw\
            rRIFkBysDdnNhubzrF66vbPjTv/3hcdPJbSgz1/GXJg1uByBqO1HgaECiZNKznnWBakBK4T2pvqREYQQsSqo9yTugQEFGbmp\
            LOPs4I/yp0MfoHZrmM1es+rkznnAUwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD9ps6fZhmN2HDYqYbzBnXEb4\
            Pi9Sg0h5UvXVBWPj73qMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4WZlxKXooAEJJPkJxkMd7ZH6G99GZch/RVimW\
            XJ1rZZT4BNkK8duJOew1/5TZZA1X3MMnlLs+G7Zv066EmoTc25QYczzLRpmklaFtCSar20CU1Xpecg0pHCVyFOEC5dShbAIF\
            BgABAA8DGwEBByEAEgYNFQEPAgobGxkEBxIQCRcWEQgbGgQHEA4LDBcUGBMQtxJGnJRtoSJg7FMAAAAAAAGC6dRmw0Z9LrKw\
            2cy+tHvb9JXuHBu0d9Dar60DX6fr5AsQCgU1JS8TAgkOAQknFQQSCzcHCAM=
            """,
        injected: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAGCaswrRIF\
            kBysDdnNhubzrF66vbPjTv/3hcdPJbSgz1/GXJg1uByBqO1HgaECiZNKznnWBakBK4T2pvqREYQQsSqo9yTugQEFGbmpLOPs4I/y\
            p0MfoHZrmM1es+rkznnAUwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD9ps6fZhmN2HDYqYbzBnXEb4Pi9Sg0h5UvXV\
            BWPj73qMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4WZlxKXooAEJJPkJxkMd7ZH6G99GZch/RVimWXJ1rZZT4BNkK8duJ\
            Oew1/5TZZA1X3MMnlLs+G7Zv066EmoTc25QDBkZv5SEXMv/srbpyw5vnvIzlu8X3EmssQ5s6QAAAABhzPMtGmaSVoW0JJqvbQJTV\
            el5yDSkcJXIU4QLl1KFsBAgABQKAGgYACAAJAyBOAAAAAAAABQYAAQAQAxwBAQchABMGDhYBEAILHBwaBAcTEQoYFxIJHBsEBxEP\
            DA0YFRkUELcSRpyUbaEiYOxTAAAAAAABgunUZsNGfS6ysNnMvrR72/SV7hwbtHfQ2q+tA1+n6+QLEAoFNSUvEwIJDgEJJxUEEgs3\
            BwgD
            """,
        unitLimit: 400000,
        feePayer: "CXFmQi2eM4Jzt9HZwm9A5JAzGvNpKwRuxo52ua3Jyceh",
        lookupTable: "9p2oT9J6BojHigd3V5qXzrwsQf4dtgMgLxtrzLVR3rwu"
    )

    // MARK: - Farm-staked withdraws, captured 2026-08-05

    /// The shape every real holder of these vaults is actually in.
    ///
    /// Deposits auto-stake into the vault's farm, so the withdraw that spends
    /// those shares has to release them first: `farms::unstake` and
    /// `farms::withdraw_unstaked_deposits`, BOTH ahead of the vault withdraw,
    /// with a second `createIdempotent` between them. Five instructions, not two.
    ///
    /// Sampled by enumerating farm `UserState` accounts rather than share-mint
    /// token-account holders — staked shares never reach the ATA, so the older
    /// method could only ever surface holders who had not staked, which is why
    /// this shape went unobserved through six steps.
    ///
    /// Every vector below simulated `err: null` on mainnet in both forms, at the
    /// 400,000 unit limit `KaminoComputeBudget.withdrawUnitLimit` now injects.
    /// At the previous 220,000 all four staked shapes aborted with
    /// `ProgramFailedToComplete — exceeded CUs meter`.

    static let stakedWithdraw = Vector(
        name: "Steakhouse USDC farm-staked withdraw (1 share)",
        source: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAGCkz4SpXM\
            eg7DW2ZzLbkMAlm0lEy/B1TiRwZqby23/jKmEZHG3rE/6w+tbzGqcJEiaHqq1pOV6hBzDAKRU/oz2gBP0vandYbwNC1pR0Jk5hEc\
            RCdjUbAG+77T/irHPNQhwVKV1ablytlLnalT6Uu+r5A74BZTGAutrI1EFMK1BOlSAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
            AAAAAAAP2mzp9mGY3YcNiphvMGdcRvg+L1KDSHlS9dUFY+PveoyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZmXEpeigA\
            Qkk+QnGQx3tkfob30ZlyH9FWKZZcnWtllPjYsBAXY9PlHxJuYVbehd6MYTBZuERo0No/6KKiJRzHAQTZCvHbiTnsNf+U2WQNV9zD\
            J5S7Phu2b9OuhJqE3NuUtL4CxGIrzRPpKB8rlnE4pZkJR/D/b08QafecDO1T5V4FBgYAAgAMBCABAQgEAAEOCBhaX2sqzXwy4QAA\
            AKHtzM4bwtMAAAAAAAAIBwABDgIRFyAIJGa7MdwkhEMGBgADABMEIAEBCSEAFgcQGgMTAgwgIB4FCRYUCxwbFQogHwUJFBINDxwZ\
            HRgQtxJGnJRtoSJAQg8AAAAAAAGC6dRmw0Z9LrKw2cy+tHvb9JXuHBu0d9Dar60DX6fr5A0QCgU1MSUvMhMCCQ4BCjMnFQQSCzcH\
            CAM=
            """,
        injected: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAHC0z4SpXM\
            eg7DW2ZzLbkMAlm0lEy/B1TiRwZqby23/jKmEZHG3rE/6w+tbzGqcJEiaHqq1pOV6hBzDAKRU/oz2gBP0vandYbwNC1pR0Jk5hEc\
            RCdjUbAG+77T/irHPNQhwVKV1ablytlLnalT6Uu+r5A74BZTGAutrI1EFMK1BOlSAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
            AAAAAAAP2mzp9mGY3YcNiphvMGdcRvg+L1KDSHlS9dUFY+PveoyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZmXEpeigA\
            Qkk+QnGQx3tkfob30ZlyH9FWKZZcnWtllPjYsBAXY9PlHxJuYVbehd6MYTBZuERo0No/6KKiJRzHAQTZCvHbiTnsNf+U2WQNV9zD\
            J5S7Phu2b9OuhJqE3NuUAwZGb+UhFzL/7K26csOb57yM5bvF9xJrLEObOkAAAAC0vgLEYivNE+koHyuWcTilmQlH8P9vTxBp95wM\
            7VPlXgcKAAUCgBoGAAoACQMgTgAAAAAAAAYGAAIADQQhAQEIBAABDwgYWl9rKs18MuEAAACh7czOG8LTAAAAAAAACAcAAQ8CEhgh\
            CCRmuzHcJIRDBgYAAwAUBCEBAQkhABcHERsDFAINISEfBQkXFQwdHBYLISAFCRUTDhAdGh4ZELcSRpyUbaEiQEIPAAAAAAABgunU\
            ZsNGfS6ysNnMvrR72/SV7hwbtHfQ2q+tA1+n6+QNEAoFNTElLzITAgkOAQozJxUEEgs3BwgD
            """,
        unitLimit: 400000,
        feePayer: "6BTaMq25LcNDTVhheUe9UyvwWgayqFv77njymVnG8SNy",
        lookupTable: "9p2oT9J6BojHigd3V5qXzrwsQf4dtgMgLxtrzLVR3rwu"
    )

    static let stakedWithdrawMaximum = Vector(
        name: "Steakhouse USDC farm-staked withdraw at the maximum",
        source: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAGCkz4SpXM\
            eg7DW2ZzLbkMAlm0lEy/B1TiRwZqby23/jKmEZHG3rE/6w+tbzGqcJEiaHqq1pOV6hBzDAKRU/oz2gBP0vandYbwNC1pR0Jk5hEc\
            RCdjUbAG+77T/irHPNQhwVKV1ablytlLnalT6Uu+r5A74BZTGAutrI1EFMK1BOlSAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
            AAAAAAAP2mzp9mGY3YcNiphvMGdcRvg+L1KDSHlS9dUFY+PveoyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZmXEpeigA\
            Qkk+QnGQx3tkfob30ZlyH9FWKZZcnWtllPjYsBAXY9PlHxJuYVbehd6MYTBZuERo0No/6KKiJRzHAQTZCvHbiTnsNf+U2WQNV9zD\
            J5S7Phu2b9OuhJqE3NuUBphekrMVPaIqHm9brpOGOjMw+kXdBuXVkdhcPk3is+8FBgYAAgAMBCABAQgEAAEOCBhaX2sqzXwy4QAA\
            SPlfaktPJ7dwAAAAAAAIBwABDgIRFyAIJGa7MdwkhEMGBgADABMEIAEBCSEAFgcQGgMTAgwgIB4FCRYUCxwbFQogHwUJFBINDxwZ\
            HRgQtxJGnJRtoSKiOx8IAAAAAAGC6dRmw0Z9LrKw2cy+tHvb9JXuHBu0d9Dar60DX6fr5A0QCgU1MSUvMhMCCQ4BCjMnFQQSCzcH\
            CAM=
            """,
        injected: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAHC0z4SpXM\
            eg7DW2ZzLbkMAlm0lEy/B1TiRwZqby23/jKmEZHG3rE/6w+tbzGqcJEiaHqq1pOV6hBzDAKRU/oz2gBP0vandYbwNC1pR0Jk5hEc\
            RCdjUbAG+77T/irHPNQhwVKV1ablytlLnalT6Uu+r5A74BZTGAutrI1EFMK1BOlSAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
            AAAAAAAP2mzp9mGY3YcNiphvMGdcRvg+L1KDSHlS9dUFY+PveoyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZmXEpeigA\
            Qkk+QnGQx3tkfob30ZlyH9FWKZZcnWtllPjYsBAXY9PlHxJuYVbehd6MYTBZuERo0No/6KKiJRzHAQTZCvHbiTnsNf+U2WQNV9zD\
            J5S7Phu2b9OuhJqE3NuUAwZGb+UhFzL/7K26csOb57yM5bvF9xJrLEObOkAAAAAGmF6SsxU9oioeb1uuk4Y6MzD6Rd0G5dWR2Fw+\
            TeKz7wcKAAUCgBoGAAoACQMgTgAAAAAAAAYGAAIADQQhAQEIBAABDwgYWl9rKs18MuEAAEj5X2pLTye3cAAAAAAACAcAAQ8CEhgh\
            CCRmuzHcJIRDBgYAAwAUBCEBAQkhABcHERsDFAINISEfBQkXFQwdHBYLISAFCRUTDhAdGh4ZELcSRpyUbaEiojsfCAAAAAABgunU\
            ZsNGfS6ysNnMvrR72/SV7hwbtHfQ2q+tA1+n6+QNEAoFNTElLzITAgkOAQozJxUEEgs3BwgD
            """,
        unitLimit: 400000,
        feePayer: "6BTaMq25LcNDTVhheUe9UyvwWgayqFv77njymVnG8SNy",
        lookupTable: "9p2oT9J6BojHigd3V5qXzrwsQf4dtgMgLxtrzLVR3rwu"
    )

    static let stakedWithdrawSentinel = Vector(
        name: "Steakhouse USDC farm-staked withdraw, reported balance sent verbatim",
        source: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAGCkz4SpXM\
            eg7DW2ZzLbkMAlm0lEy/B1TiRwZqby23/jKmEZHG3rE/6w+tbzGqcJEiaHqq1pOV6hBzDAKRU/oz2gBP0vandYbwNC1pR0Jk5hEc\
            RCdjUbAG+77T/irHPNQhwVKV1ablytlLnalT6Uu+r5A74BZTGAutrI1EFMK1BOlSAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
            AAAAAAAP2mzp9mGY3YcNiphvMGdcRvg+L1KDSHlS9dUFY+PveoyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZmXEpeigA\
            Qkk+QnGQx3tkfob30ZlyH9FWKZZcnWtllPjYsBAXY9PlHxJuYVbehd6MYTBZuERo0No/6KKiJRzHAQTZCvHbiTnsNf+U2WQNV9zD\
            J5S7Phu2b9OuhJqE3NuUbuf+XWbOlC3529elQcGMuE9HTp+9RtIczwCiV4HySwgFBgYAAgAMBCABAQgEAAEOCBhaX2sqzXwy4QAA\
            SPlfaktPJ7dwAAAAAAAIBwABDgIRFyAIJGa7MdwkhEMGBgADABMEIAEBCSEAFgcQGgMTAgwgIB4FCRYUCxwbFQogHwUJFBINDxwZ\
            HRgQtxJGnJRtoSL//////////wGC6dRmw0Z9LrKw2cy+tHvb9JXuHBu0d9Dar60DX6fr5A0QCgU1MSUvMhMCCQ4BCjMnFQQSCzcH\
            CAM=
            """,
        injected: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAHC0z4SpXM\
            eg7DW2ZzLbkMAlm0lEy/B1TiRwZqby23/jKmEZHG3rE/6w+tbzGqcJEiaHqq1pOV6hBzDAKRU/oz2gBP0vandYbwNC1pR0Jk5hEc\
            RCdjUbAG+77T/irHPNQhwVKV1ablytlLnalT6Uu+r5A74BZTGAutrI1EFMK1BOlSAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
            AAAAAAAP2mzp9mGY3YcNiphvMGdcRvg+L1KDSHlS9dUFY+PveoyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZmXEpeigA\
            Qkk+QnGQx3tkfob30ZlyH9FWKZZcnWtllPjYsBAXY9PlHxJuYVbehd6MYTBZuERo0No/6KKiJRzHAQTZCvHbiTnsNf+U2WQNV9zD\
            J5S7Phu2b9OuhJqE3NuUAwZGb+UhFzL/7K26csOb57yM5bvF9xJrLEObOkAAAABu5/5dZs6ULfnb16VBwYy4T0dOn71G0hzPAKJX\
            gfJLCAcKAAUCgBoGAAoACQMgTgAAAAAAAAYGAAIADQQhAQEIBAABDwgYWl9rKs18MuEAAEj5X2pLTye3cAAAAAAACAcAAQ8CEhgh\
            CCRmuzHcJIRDBgYAAwAUBCEBAQkhABcHERsDFAINISEfBQkXFQwdHBYLISAFCRUTDhAdGh4ZELcSRpyUbaEi//////////8BgunU\
            ZsNGfS6ysNnMvrR72/SV7hwbtHfQ2q+tA1+n6+QNEAoFNTElLzITAgkOAQozJxUEEgs3BwgD
            """,
        unitLimit: 400000,
        feePayer: "6BTaMq25LcNDTVhheUe9UyvwWgayqFv77njymVnG8SNy",
        lookupTable: "9p2oT9J6BojHigd3V5qXzrwsQf4dtgMgLxtrzLVR3rwu"
    )

    static let mixedWithdrawStraddling = Vector(
        name: "Steakhouse USDC mixed position, request above the unstaked balance",
        source: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAGCryY4hyc\
            YhNaRK0DrigDccg2zc2iZlitrRXU59g3Ge7FxLQfCdiS5oA7TsQFf/YV/ZuGEwJDm6YspUdyhGq8T3b6Wwp7azb/96qwFWVdDW1M\
            Z5DPH9mE5Unsl/XHNsrdx/7cnvMaAxxvMYRasNMMnRXWNPhl4Z1xlK/NNwsZyXiQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
            AAAAAAAP2mzp9mGY3YcNiphvMGdcRvg+L1KDSHlS9dUFY+PveoyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZmXEpeigA\
            Qkk+QnGQx3tkfob30ZlyH9FWKZZcnWtllPjYsBAXY9PlHxJuYVbehd6MYTBZuERo0No/6KKiJRzHAQTZCvHbiTnsNf+U2WQNV9zD\
            J5S7Phu2b9OuhJqE3NuUu441xnHog9/eD3w8ACa6kHg/wl58PQW1mukPaOm4G9wFBgYAAgAMBCABAQgEAAMOCBhaX2sqzXwy4QAA\
            fLkABa2Fb3IAAAAAAAAIBwADDgIRFyAIJGa7MdwkhEMGBgABABMEIAEBCSEAFgcQGgETAgwgIB4FCRYUCxwbFQogHwUJFBINDxwZ\
            HRgQtxJGnJRtoSJg4xYAAAAAAAGC6dRmw0Z9LrKw2cy+tHvb9JXuHBu0d9Dar60DX6fr5A0QCgU1MSUvMhMCCQ4BCjMnFQQSCzcH\
            CAM=
            """,
        injected: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAHC7yY4hyc\
            YhNaRK0DrigDccg2zc2iZlitrRXU59g3Ge7FxLQfCdiS5oA7TsQFf/YV/ZuGEwJDm6YspUdyhGq8T3b6Wwp7azb/96qwFWVdDW1M\
            Z5DPH9mE5Unsl/XHNsrdx/7cnvMaAxxvMYRasNMMnRXWNPhl4Z1xlK/NNwsZyXiQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\
            AAAAAAAP2mzp9mGY3YcNiphvMGdcRvg+L1KDSHlS9dUFY+PveoyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZmXEpeigA\
            Qkk+QnGQx3tkfob30ZlyH9FWKZZcnWtllPjYsBAXY9PlHxJuYVbehd6MYTBZuERo0No/6KKiJRzHAQTZCvHbiTnsNf+U2WQNV9zD\
            J5S7Phu2b9OuhJqE3NuUAwZGb+UhFzL/7K26csOb57yM5bvF9xJrLEObOkAAAAC7jjXGceiD394PfDwAJrqQeD/CXnw9BbWa6Q9o\
            6bgb3AcKAAUCgBoGAAoACQMgTgAAAAAAAAYGAAIADQQhAQEIBAADDwgYWl9rKs18MuEAAHy5AAWthW9yAAAAAAAACAcAAw8CEhgh\
            CCRmuzHcJIRDBgYAAQAUBCEBAQkhABcHERsBFAINISEfBQkXFQwdHBYLISAFCRUTDhAdGh4ZELcSRpyUbaEiYOMWAAAAAAABgunU\
            ZsNGfS6ysNnMvrR72/SV7hwbtHfQ2q+tA1+n6+QNEAoFNTElLzITAgkOAQozJxUEEgs3BwgD
            """,
        unitLimit: 400000,
        feePayer: "DhCrkyWYGQayd4QNUDdLyvrALLmrJqTUHPGoA98pX2YU",
        lookupTable: "9p2oT9J6BojHigd3V5qXzrwsQf4dtgMgLxtrzLVR3rwu"
    )

    static let mixedWithdrawWithinUnstaked = Vector(
        name: "Steakhouse USDC mixed position, request inside the unstaked balance",
        source: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAFCLyY4hyc\
            YhNaRK0DrigDccg2zc2iZlitrRXU59g3Ge7FxLQfCdiS5oA7TsQFf/YV/ZuGEwJDm6YspUdyhGq8T3b6Wwp7azb/96qwFWVdDW1M\
            Z5DPH9mE5Unsl/XHNsrdxwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD9ps6fZhmN2HDYqYbzBnXEb4Pi9Sg0h5UvXV\
            BWPj73qMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4WZlxKXooAEJJPkJxkMd7ZH6G99GZch/RVimWXJ1rZZT4BNkK8duJ\
            Oew1/5TZZA1X3MMnlLs+G7Zv066EmoTc25TGHIArL9bIi1dPO/AGld0dxV8XdwWe6ukSPeMFcDkozQIFBgABAA8DGwEBByEAEgYN\
            FQEPAgobGxkEBxIQCRcWEQgbGgQHEA4LDBcUGBMQtxJGnJRtoSIgoQcAAAAAAAGC6dRmw0Z9LrKw2cy+tHvb9JXuHBu0d9Dar60D\
            X6fr5AsQCgU1JS8TAgkOAQknFQQSCzcHCAM=
            """,
        injected: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAGCbyY4hyc\
            YhNaRK0DrigDccg2zc2iZlitrRXU59g3Ge7FxLQfCdiS5oA7TsQFf/YV/ZuGEwJDm6YspUdyhGq8T3b6Wwp7azb/96qwFWVdDW1M\
            Z5DPH9mE5Unsl/XHNsrdxwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD9ps6fZhmN2HDYqYbzBnXEb4Pi9Sg0h5UvXV\
            BWPj73qMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4WZlxKXooAEJJPkJxkMd7ZH6G99GZch/RVimWXJ1rZZT4BNkK8duJ\
            Oew1/5TZZA1X3MMnlLs+G7Zv066EmoTc25QDBkZv5SEXMv/srbpyw5vnvIzlu8X3EmssQ5s6QAAAAMYcgCsv1siLV0878AaV3R3F\
            Xxd3BZ7q6RI94wVwOSjNBAgABQKAGgYACAAJAyBOAAAAAAAABQYAAQAQAxwBAQchABMGDhYBEAILHBwaBAcTEQoYFxIJHBsEBxEP\
            DA0YFRkUELcSRpyUbaEiIKEHAAAAAAABgunUZsNGfS6ysNnMvrR72/SV7hwbtHfQ2q+tA1+n6+QLEAoFNSUvEwIJDgEJJxUEEgs3\
            BwgD
            """,
        unitLimit: 400000,
        feePayer: "DhCrkyWYGQayd4QNUDdLyvrALLmrJqTUHPGoA98pX2YU",
        lookupTable: "9p2oT9J6BojHigd3V5qXzrwsQf4dtgMgLxtrzLVR3rwu"
    )

    static let solStakedWithdraw = Vector(
        name: "Allez SOL farm-staked withdraw (1 share)",
        source: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAHDaeaaKZP\
            jZPHIsEWiaq8CpV7zagmikPKg3uO3CGNVGHIAAbz7Jt9F3fAE6VPfali143o90zDJw70OVOjdlQqAgUmd32krI1abytflYxaVpGk\
            S5piwAx3/S4qTYc24guoU1KIQ+MtZQ6U96hn3M2pZCLsAUWI/+CTZnW8t5ew+Yo4XVZFPiktKAME876706kc+sJJQpKC66bDAwbL\
            HRdKrQP6HoLYlf5IbdNEuFQby9p5byRMsWwK5OpCzyixXzveqA/abOn2YZjdhw2KmG8wZ1xG+D4vUoNIeVL11QVj4+96XeboxRMf\
            AIUjdma/pYmB40SyAoUCiU72pB4ZlbqjfOiMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4WZlxKXooAEJJPkJxkMd7ZH6G\
            99GZch/RVimWXJ1rZZT42LAQF2PT5R8SbmFW3oXejGEwWbhEaNDaP+iioiUcxwEE2Qrx24k57DX/lNlkDVfcwyeUuz4btm/TroSa\
            hNzblAbd9uHXZaGT2cvhRs7reawctIXtX1s3kTqM9YV+/wCpjUo01QF7ze780sQTwucxbrHhnU3VVixSKrJohI6ZJXcGCAYABAAV\
            GgwBAQoEAAEWChhaX2sqzXwy4QAAAKHtzM4bwtMAAAAAAAAKBwABFgQCBwwIJGa7MdwkhEMIBgADABgaDAEBCyUAEAkFHAMYBBUM\
            DCMGCxAPEiIeGRQMJAYLDxEOFxMNIhsdHyEgELcSRpyUbaEiQEIPAAAAAAAMAwMAAAEJAVy8CS9SBiaWlGOa3Uxf3wjMD/16XND2\
            V35Wz/IAd5jIDVsbCQESCjwPBVAxAg0LHhQEHREzSD4LBwg=
            """,
        injected: """
            AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAQAIDqeaaKZP\
            jZPHIsEWiaq8CpV7zagmikPKg3uO3CGNVGHIAAbz7Jt9F3fAE6VPfali143o90zDJw70OVOjdlQqAgUmd32krI1abytflYxaVpGk\
            S5piwAx3/S4qTYc24guoU1KIQ+MtZQ6U96hn3M2pZCLsAUWI/+CTZnW8t5ew+Yo4XVZFPiktKAME876706kc+sJJQpKC66bDAwbL\
            HRdKrQP6HoLYlf5IbdNEuFQby9p5byRMsWwK5OpCzyixXzveqA/abOn2YZjdhw2KmG8wZ1xG+D4vUoNIeVL11QVj4+96XeboxRMf\
            AIUjdma/pYmB40SyAoUCiU72pB4ZlbqjfOiMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4WZlxKXooAEJJPkJxkMd7ZH6G\
            99GZch/RVimWXJ1rZZT42LAQF2PT5R8SbmFW3oXejGEwWbhEaNDaP+iioiUcxwEE2Qrx24k57DX/lNlkDVfcwyeUuz4btm/TroSa\
            hNzblAbd9uHXZaGT2cvhRs7reawctIXtX1s3kTqM9YV+/wCpAwZGb+UhFzL/7K26csOb57yM5bvF9xJrLEObOkAAAACNSjTVAXvN\
            7vzSxBPC5zFuseGdTdVWLFIqsmiEjpkldwgNAAUCgBoGAA0ACQMgTgAAAAAAAAgGAAQAFhsMAQEKBAABFwoYWl9rKs18MuEAAACh\
            7czOG8LTAAAAAAAACgcAARcEAgcMCCRmuzHcJIRDCAYAAwAZGwwBAQslABEJBR0DGQQWDAwkBgsREBMjHxoVDCUGCxASDxgUDiMc\
            HiAiIRC3EkaclG2hIkBCDwAAAAAADAMDAAABCQFcvAkvUgYmlpRjmt1MX98IzA/9elzQ9ld+Vs/yAHeYyA1bGwkBEgo8DwVQMQIN\
            Cx4UBB0RM0g+CwcI
            """,
        unitLimit: 400000,
        feePayer: "CHFeSGER1nXFUtvdAVb49rLHTgvvuxEXmeTG3GBtgKzF",
        lookupTable: "7EzosNioQ6FDNvMKLfg6om5wTVHiJo9vVx7DZNGYBKU3"
    )

    static let all: [Vector] = [
        usdcDeposit,
        solDeposit,
        usdcWithdraw,
        stakedWithdraw,
        stakedWithdrawMaximum,
        mixedWithdrawStraddling,
        mixedWithdrawWithinUnstaked,
        solStakedWithdraw
    ]

    /// Deliberately NOT in `all`. This is the transaction the API builds when
    /// the reported `stakedShares` string — 14 decimal places on a 6-decimal
    /// mint — is handed straight back as the amount: its vault-withdraw `u64` is
    /// the `u64::MAX` withdraw-everything sentinel, so it is a vector the app
    /// must REFUSE rather than round-trip.
    static let refusedVectors: [Vector] = [stakedWithdrawSentinel]

    /// Address lookup table contents, keyed by table address — read from mainnet
    /// with `getAccountInfo` on 2026-08-04. A lookup table is append-only unless
    /// it is deactivated wholesale, so the prefix these transactions index into
    /// is stable.
    ///
    /// These are what make the golden tests mean something. An account index is
    /// only a position, so showing that an edit preserved the *indices* shows
    /// nothing; resolving both sides through the real table shows the edit
    /// preserved the account *pubkeys* every instruction receives.
    static let lookupTables: [String: [String]] = [
        "9p2oT9J6BojHigd3V5qXzrwsQf4dtgMgLxtrzLVR3rwu": [
            "sadmBTQm5HJsyzWHEjV4YwG9CiahZKVDVqAyS4Wx1zH",
            "HDsayqAsDWy3QvANGqh2yNraqcD8Fnjgh73Mhb3WRS5E",
            "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            "AyY6VCkHfTWdFs7SqBbu6AnCqLUhgzVHBzW3WcJu5Jc8",
            "7D8C5pDFxug58L9zkwK7bCiDg4kD4AygzbcZUmf5usHS",
            "SysvarRent111111111111111111111111111111111",
            "KLend2g3cP87fffoy8q1mQqGKjrxjC8boSyAYavgmjD",
            "Sysvar1nstructions1111111111111111111111111",
            "Ga4rZytCpq1unD4DbEJ5bkHeUz9g3oh9AAFEi6vSauXp",
            "5rGkiF4Jf1rPTJ6nazBgcjewVktXhagwcw5Nux7GccRi",
            "DxXdAyU3kCjnyggvHmY5nAwg5cRbbmdyX3npfDMjjMek",
            "EGDhupegCXLtonYDSY67c4dzw86S9eMxsntQ1yxWSoHv",
            "B7nzBEuViVtaQN8iEhhtBY4gQSxBY38ms31DUWUx1bza",
            "GENey8es3EgGiNTM8H8gzA3vf98haQF8LHiYFyErjgrv",
            "rywFxeqHfCWL5iGq9cDxutwiiR2TabZgzv8aRM1Lceq",
            "32XLsweyeQwWgLKRVAzS72nxHGU1JmmNQQZ3C3q6fBjJ",
            "6WnymZBTAekuHf9DgsaDKJ397oEZ3qMApNMHg9qjqhgm",
            "B9spsrMK6pJicYtukaZzDyzsUQLgc3jbx5gHVwdDxb6y",
            "D6q6wuQSrifJKZYpR1M8R4YawnLDtDsMmWM1NbBmgJ59",
            "CZg8x8oqB7FYUfURq15F5AcjRTymcXsc8ann76CrpJrf",
            "7u3HeHxYDLhnCoErrtycNokbQYbWGzLs6JSDqGAv5PfF",
            "JAvnB9AKtgPsTEoKmn24Bq64UMoYcrtWtq42HHBdsPkh",
            "Bgq7trRgVMeq33yt235zM2onQ4bRDBsY5EWiTetF4qw6",
            "BbDUrk1bVtSixgQsPLBJFZEF7mwGstnD5joA1WzYvYFX",
            "B8V6WVjPxW1UGwVDfxH2d2r8SyT4cqn7dQRK6XneVa7D",
            "3DzjXRfxRm6iejfyyMynR4tScddaanrePJ1NJU2XnPPL",
            "9DrvZvyWh1HuAoZxvYWMvkf2XCzryCpGgHqrMjyDWpmo",
            "9TD2TSv4pENb8VwfbVYg25jvym7HN6iuAR6pFNSrKjqQ",
            "DNcUGqKJ8SD2uEmmWmzsTiZ8xbNc6UBYM8yzdTex9kgE",
            "ByYiZxp8QrdN9qbdtaAiePN8AAr3qvTPppNJDpf5DVJ5",
            "23UsLhyeuZBCRJNVFkPrmMCfXuka8hQa8S6spXwTEHcc",
            "HTyrXvSvBbD7WstvU3oqFTBZM1fPZJPxVRvwLAmCTDyJ",
            "9CvpyHx3FHJfrMcdCYMS5CaCucov5VSzJ3pyzs7RJ8r6",
            "A2mcvn3kQXwG9XPUPgjghXJDqvYHTpkCJE3wtKqU1VRn",
            "8bGWMt65Y7RV2DV5sxNRxFM5jsUhBMSo8u24pbRPjQLY",
            "81BgcfZuZf9bESLvw3zDkh7cZmMtDwTPgkCvYu7zx26o",
            "Atj6UREVWa7WxbF2EMKNyfmYUY1U1txughe2gjhcPDCo",
            "Hq8LJAn7scQSBCNysRtrRXuZYNvZ5MRpbqK7T3JyLYqc",
            "6WEGfej9B9wjxRs6t4BYpb9iCXd8CpTpJ8fVSNzHCC5y",
            "6Y9fzrWzGZaxdAJ2eWRg9UZpL3kqPDiVXAb67KJpWdUg",
            "BBcwMNSMyhhBnYE9pevEvkxKHGzTafMP9v3j7Kk7nAWM",
            "HH7GLnRcGHJrdkEueVVj7mccNUjnSeWobDmtu9cHLkJV",
            "6M89FWrQaqcy3domy85J1a1wVMnviL86WeUqbqTXf1qb",
            "25x4aEFoJE3bk4sdNLgHrrmchyop1JvcmGA4ccA6tWWT",
            "6QbtpY2jDNcncRFmVf343NThnCdaY8gCAsYATPnYQR9g",
            "9ceRgz579BcfWogs3RE11FKNQaWW7Lmtnev3MXspxUjF",
            "CKTEDx5z19CntAB9B66AxuS98S1NuCgMvfpsew7TQwi",
            "87gUNr8LwYJCT25HjPEHnrfBBjwEMAjfqCfnKcJNqy9Y",
            "9FVjHqduhDPMVqvu3cXiEBjU6nvxvGdCCLRwd9WpVRZj",
            "CRsf9nPkGBUT1HDytxfoYe3PBa5CZc9Nsh9a5aoBbGnb",
            "45AYN1NotDSbptLmfPrV31nrbZktJ6DLJKBxQbJMBxYg",
            "6UodrBjL2ZreDy7QdR4YV1oxqMBjVYSEyrFpctqqwGwL",
            "9FRZvAsjDJ6WM8BJ2S45h9PoDCLAq8DNY9zZDX7MyGzT",
            "Dc2gueqz9FkChnKNEwBFf5enu7hhuiFWFjGCkUaXawR5",
            "GMqmFygF5iSm5nkckYU6tieggFcR42SyjkkhK5rswFRs",
            "BtKurxqKCCpL6bgvpfPskT2F5pjynnwgTJKF8REAQm1T",
            "6sHZvPZLVPqG5HPguW13UbfoGvqb3VRsa5NkBBdj7gjw",
            "5J8om3Mwx8FGuu3GaD29ibRLtjX9z1ZK3oX112ruUheG",
            "5zUFYbpFbapqWSuTpGS7X2PD1cs1pDaoFtqm4UK4fRV9",
            "5Qb9RJCA1ZNTjLK4TNTNm3L2YtpbxQajtkqg6vWDdB2T"
        ],
        "7EzosNioQ6FDNvMKLfg6om5wTVHiJo9vVx7DZNGYBKU3": [
            "FU76ac2Hm2mo4hoyckhAKDrbKTFwxyDPHnrrERfMXusE",
            "A1so1bPD3W1TfeFwboDh8yfAAVaVtcdAYBYCjhg2mJQ",
            "So11111111111111111111111111111111111111112",
            "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            "89icm3xw75kZV9Cu7UkbkXj1F1iZeJdQeF1cxtkfHYUr",
            "FiM4VQdXXnTXL7GgChryf9zHNG9cmvKECwf34L2y3CkN",
            "SysvarRent111111111111111111111111111111111",
            "KLend2g3cP87fffoy8q1mQqGKjrxjC8boSyAYavgmjD",
            "Sysvar1nstructions1111111111111111111111111",
            "6gTJfuPHEg6uRAijRkMqNc9kan4sVZejKMxmvx2grT1p",
            "Dcna6zQFf4BzBWK8nnDAcgjBPPAe5Mj4LZ7TvtqnzWpT",
            "H6rHXmXoCQvq8Ue81MqNh7ow5ysPa1dSozwW3PU1dDH6",
            "BgMEUzcjkJxEH1PdPkZyv3NbUynwbkPiNJ7X2x7G1JmH",
            "ywaaLvG7t1vXJo8sT3UzE8yzzZtxLM7Fmev64Jbooye",
            "EQ7hw63aBS7aPQqXsoxaaBxiwbEzaAiY9Js6tCekkqxf",
            "DxzDt5kPdFkMy9AANiZh4zuoitobqsn1G6bdoNyjePC2",
            "8qnXfbaLbY6Y4xiCP6SZ3RK8ccjVa8DhALzDGifBPeNx",
            "Dx8iy2o46sK1DzWbEcznqSKeLbLVeu7otkibA3WohGAj",
            "d4A2prbA2whesmvHaL88BH6Ewn5N4bTSU2Ze8P6Bc4Q",
            "BpjUkkRUfEoHNz6ghe2ETwKZtRvy3E6RBuYehjYiwxds",
            "7u3HeHxYDLhnCoErrtycNokbQYbWGzLs6JSDqGAv5PfF",
            "955xWFhSDcDiUgUr4sBRtCpTLiMd4H5uZLAmgtP3R3sX",
            "GafNuUXj9rxGLn4y79dPu6MHSuPWeJR6UtTWuexpGh3U",
            "3JNof8s453bwG5UqiXBLJc77NRQXezYYEBbk3fqnoKph",
            "2UywZrUdyqs5vDchy7fKQJKau2RVyuzBev2XKGPDSiX1",
            "8NXMyRD91p3nof61BTkJvrfpGTASHygz1cUvc3HvwyGS",
            "9DrvZvyWh1HuAoZxvYWMvkf2XCzryCpGgHqrMjyDWpmo",
            "4oigbthMAgjTMPyw8dBxhxU59YMtvNDHqhpR3W4HAzBM",
            "3kJUKfsaYZZ4LpuRxw47FKemey8TwpMJkDGFNbfSwMYj",
            "C7h9YnjPrDvNhe2cWWDhCu4CZEB1XTTH4RzjmsHuengV",
            "11111111111111111111111111111111",
            "11111111111111111111111111111111",
            "So11111111111111111111111111111111111111112",
            "3SdrFTt4Ye5yppzpT9axNMj8W1x71nDYXdjv7vDuBpnR",
            "DW718KwF5d9URykynv8dcmHSQNXKTv7V5VxW5ozckbGS",
            "BDvpFVD23XCRUCoznyeUHFRU4HfNuAn2KEnMoj7PDGsd",
            "2yD1e9jGqwnQ4BXasTdL2Y3eGbmsmzeBtfX9yNL2kTXv",
            "69rYv5ucrCvhL3k8MnaSaySa2Eqivv6ee8FjcpUvviRK",
            "4RcnUDXjrr4Fj36ZfwhqJ32s14ziXWHLBjorMrdkDcfV",
            "49SoZGy2gJ5U3EN8rumKhGVXmoTT42eozySajgyENKGm",
            "CuSNbDHVEXGfptpnbDRW5VxTRhGsz7BrudK95cJhH8uV",
            "11111111111111111111111111111111",
            "11111111111111111111111111111111",
            "So11111111111111111111111111111111111111112",
            "2qYqGguuNMruP3wZ5xHRYkpom6Ha4hSMYQQFCBpTAVck",
            "Acpag5AsMAqmd1zS8qKrb2xMvKsUAZQ3JeyBg93aHAd6",
            "CQZ3NWdDpADRPjgLP281Qq34E7sQCHfCjkkXemxKnsju",
            "7VLjLyJe6GrdvGJNyDS5nPTCptLT9Uy4pFJjP7hxskpt",
            "8gUWLhFzxh6b22poaUhbm5GkZp6j4Q2eXsGiuDnMvFNx",
            "HaVsdBb4mMoYQ3vnS7wCdvhixg5xFQALmFwyL9QJm3fn",
            "Dr1V9swXjxY9xa3hQnMVu5CpLV1fMQenWf6io8cJfBA7",
            "eNLm5e5KVDX2vEcCkt75PpZ2GMfXcZES3QrFshgpVzp",
            "11111111111111111111111111111111",
            "11111111111111111111111111111111",
            "So11111111111111111111111111111111111111112",
            "5CKcCjoNrcwegdLFuBxa3HJBaJsnHHhTYaJPwcEwh69u",
            "HT7Z98Y6FgiDet1QCQPPQr8at72hnDC1hUSdQhhjhVdg",
            "C558WZD2BMrZikgoDbs9GMHNaMVournUnxyySxGmL8w9",
            "AS7jFm5TVMu1y2t9YoyXmcBNMkTBeXmDETVu1t8Siixs",
            "3DiGQ4cKL1NLVh2VG7LrhqGw5PsoLXJsYawzkwFUkW8d",
            "DQ126djx5db6SMCbejHLNxoosonVes3qW5eVVUQuT93v",
            "E4ajZm5WVE6kU4z4YWhQvMQXZhB3r91ga5Hf88mNDAzU",
            "GVDUXFwS8uvBG35RjZv6Y8S1AkV5uASiMJ9qTUKqb5PL",
            "9C3ZmYzfkYLfUDyCoRR4sxYYUNSQJFEXK8FtJuomnQk9",
            "3VP8AjMBLmRNJ199QP6iaBG9LZYCkukXpV5ePm8ov66i",
            "So11111111111111111111111111111111111111112",
            "BSqBirnJMQnRFCq8EEhx4z2nJTMKHxgVLqchwyzSdESL",
            "6uDSbrsGiUnsCDubqsXAQA3Zs4tAii2v3P52M3WuYpeQ",
            "3EDSt29jGSz69ZQmxuWrsvHJqmztr8wyUjvn9x41uAca",
            "BmesT6HkmXWHuLDf7CkdMt81rx5GSgy4JFLyMezwSJ1Z",
            "Gi2fcYkNMP4Gv88oaZt7D27mkeMW6wv8E5GZnN1eSQgt",
            "A11EznxnJM3JrjUvAq16wqoVyPRNz522mdQm6mSmzMeR",
            "F4Pn9mAvbUazDmWET5yYATTiyLHLaCRTWgGex4tiMXAs",
            "CJVpkUjja7dvgavxsH66KFrUrNCfEqW2tL1sPrYcc3jt",
            "5dLLmbTgxZg6eSmvvrmE7JqtoXGnPGKbB4qRCmrbbYBK",
            "5WkWedGR2eeSSTSzHivdYoHNuz9Rv1tMxmaFdDBJGvzz",
            "FwWtRufokc1U2q8mcLLnW3k2TvguQ4z8bAkdzG155ohJ",
            "HTpShnvV8hwaaLuJygzXqGEz45g22fGJxmdxpuy7XGi5",
            "96QTa6oKGwwvg9fRuy5knVqLfhHDAqxYzEGLzLVe7Dzu",
            "2N7x2mPkJKuSuVwTSSY8pwba7EGZLfPF8thUsJY6xU8v",
            "H6kauPaHmNqpdKtD5U2zw3Eb28ZB7iMeBdHVfLq1i4Kh",
            "BZC1zqPDiBDF3aRWk4cQqiLhJ6wYeeWu2eZr7MoztoyG",
            "GNDisPNo6MUHvSavZYqnUD8rsC9B2FaHzchk1TnLaQKo",
            "3j5Sy3LUrEgXHNtnsstKrk54F9WxQmNvbY7w8UTrztWe",
            "6vSidHXvxYEZL53wVZioSys9r8WAjh9KoH7T9K3satrw",
            "DyP2zKye4AZ8gKeUexFqa3niHUNusUhh4TmKZJfd1YWh",
            "BLYBTU5L5wuENyFX1m7rBChRzNELxRpskq4U4YYkd46i",
            "8GWJgq9wks1KERyXtpJ6fJLPuVkBwKuRN2LCnJCGeu4J",
            "9wgvjvrk2Ru3w5getmMA9YEgXrdDFirMsrU2EoSU2DYh",
            "BgoNQ9hKXbhvWdQqVZYEr2QAkhyPN7XwoT38pw1m4DnS",
            "Cj1SVEpEi4tsZqmR8AguXRUkWWv1C22scPu4QxTGSxhN",
            "3Mf2mmocNbNAc7KS9QmANGEv9BcgwbT1tLRBuruGCdu5",
            "t2VnpiTyoahHuB8ibJj986DmkURxjSKtUqbtqstzEQi",
            "BZC1zqPDiBDF3aRWk4cQqiLhJ6wYeeWu2eZr7MoztoyG",
            "GNDisPNo6MUHvSavZYqnUD8rsC9B2FaHzchk1TnLaQKo",
            "3j5Sy3LUrEgXHNtnsstKrk54F9WxQmNvbY7w8UTrztWe",
            "6vSidHXvxYEZL53wVZioSys9r8WAjh9KoH7T9K3satrw",
            "DyP2zKye4AZ8gKeUexFqa3niHUNusUhh4TmKZJfd1YWh",
            "BLYBTU5L5wuENyFX1m7rBChRzNELxRpskq4U4YYkd46i"
        ]
    ]
}
