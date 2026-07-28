import Foundation

class TokensStore {

    static let TokenSelectionAssets = [
        CoinMeta(
            chain: .akash,
            ticker: "AKT",
            logo: "akash",
            decimals: 6,
            priceProviderId: "akash-network",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .hyperliquid,
            ticker: "HYPE",
            logo: "hyperliquid",
            decimals: 18,
            priceProviderId: "hyperliquid",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .hyperliquid,
            ticker: "kHYPE",
            logo: "khype",
            decimals: 18,
            priceProviderId: "kinetic-staked-hype",
            contractAddress: "0xfD739d4e423301CE9385c1fb8850539D657C296D",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .hyperliquid,
            ticker: "wstHYPE",
            logo: "wsthype",
            decimals: 18,
            priceProviderId: "staked-hype-shares",
            contractAddress: "0x94e8396e0869c9F2200760aF0621aFd240E1CF38",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .hyperliquid,
            ticker: "WHYPE",
            logo: "whype",
            decimals: 18,
            priceProviderId: "wrapped-hype",
            contractAddress: "0x5555555555555555555555555555555555555555",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .hyperliquid,
            ticker: "UFART",
            logo: "ufart",
            decimals: 6,
            priceProviderId: "unit-fartcoin",
            contractAddress: "0x3B4575E689DEd21CAAD31d64C4df1f10F3B2CedF",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .hyperliquid,
            ticker: "USDT0",
            logo: "usdt0",
            decimals: 6,
            priceProviderId: "usdt0",
            contractAddress: "0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .hyperliquid,
            ticker: "vkHYPE",
            logo: "vkhype",
            decimals: 18,
            priceProviderId: "kinetiq-earn-vault",
            contractAddress: "0x9BA2EDc44E0A4632EB4723E81d4142353e1bB160",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .hyperliquid,
            ticker: "UBTC",
            logo: "ubtc",
            decimals: 8,
            priceProviderId: "unit-bitcoin",
            contractAddress: "0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .hyperliquid,
            ticker: "vHYPE",
            logo: "vhype",
            decimals: 18,
            priceProviderId: "ventuals-vhype",
            contractAddress: "0x8888888FdAAc0E7CF8C6523c8955bF7954c216fa",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .hyperliquid,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0xb88339CB7199b77E23DB6E890353E22632Ba630f",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "USDG",
            logo: "usdg",
            decimals: 6,
            priceProviderId: "global-dollar",
            contractAddress: "0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "USDe",
            logo: "usde",
            decimals: 18,
            priceProviderId: "ethena-usde",
            contractAddress: "0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "WETH",
            logo: "weth",
            decimals: 18,
            priceProviderId: "weth",
            contractAddress: "0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "LINK",
            logo: "link",
            decimals: 18,
            priceProviderId: "chainlink",
            contractAddress: "0x492641F648a4986844848E0beFE66D14817bCE34",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "AAOI",
            logo: "https://financialmodelingprep.com/image-stock/AAOI.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x521Cf887E6531c6F667b5BC4D896E5d9bfE8EB2E",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "AAPL",
            logo: "https://financialmodelingprep.com/image-stock/AAPL.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "AMAT",
            logo: "https://financialmodelingprep.com/image-stock/AMAT.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x36046893810a7E7fCE501229d57dc3FC8c8716d0",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "AMD",
            logo: "https://financialmodelingprep.com/image-stock/AMD.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x86923f96303D656E4aa86D9d42D1e57ad2023fdC",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "AMZN",
            logo: "https://financialmodelingprep.com/image-stock/AMZN.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x12f190a9F9d7D37a250758b26824B97CE941bF54",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "APLD",
            logo: "https://financialmodelingprep.com/image-stock/APLD.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xb8DBf92F9741c9ac1c32115E78581f23509916FD",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "ASML",
            logo: "https://financialmodelingprep.com/image-stock/ASML.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x47F93d52cBeC7C6D2CfC080e154002370a60dAEA",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "ASTS",
            logo: "https://financialmodelingprep.com/image-stock/ASTS.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x1AF6446f07eb1d97c546AFC8c9544cBDF3AD5137",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "AVGO",
            logo: "https://financialmodelingprep.com/image-stock/AVGO.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x156E175DD063a8cE274C50654eF40e0032b3fbcF",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "BA",
            logo: "https://financialmodelingprep.com/image-stock/BA.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x4D21483a44Bf67a86b77E3dA301411880797D452",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "BABA",
            logo: "https://financialmodelingprep.com/image-stock/BABA.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xad25Ac6C84D497db898fa1E8387bf6Af3532a1c4",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "BE",
            logo: "https://financialmodelingprep.com/image-stock/BE.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x822CC93fFD030293E9842c30BBD678F530701867",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "CBRS",
            logo: "https://financialmodelingprep.com/image-stock/CBRS.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x5c90450Bbb4273D7b2f17CF6917AEB237A569679",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "CCL",
            logo: "https://financialmodelingprep.com/image-stock/CCL.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x9651342CeA770aE9a2969Ba2A52611523146aef9",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "CELH",
            logo: "https://financialmodelingprep.com/image-stock/CELH.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x8cF07C5A878945185d327aAa6e33FAa95F95e7bF",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "CLSK",
            logo: "https://financialmodelingprep.com/image-stock/CLSK.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xcBB95BBF36099d34dA091dc6Fa6F49EfA257Cee3",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "COIN",
            logo: "https://financialmodelingprep.com/image-stock/COIN.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x6330D8C3178a418788dF01a47479c0ce7CCF450b",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "COST",
            logo: "https://financialmodelingprep.com/image-stock/COST.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x4EA005168D7F09a7A0Ba9D1DEf21a479950E44C2",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "CRCL",
            logo: "https://financialmodelingprep.com/image-stock/CRCL.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xdF0992E440dD0be65BD8439b609d6D4366bf1CB5",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "CRWD",
            logo: "https://financialmodelingprep.com/image-stock/CRWD.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "CRWV",
            logo: "https://financialmodelingprep.com/image-stock/CRWV.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x5f10A1C971B69e47e059e1dC91901B59b3fB49C3",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "DDOG",
            logo: "https://financialmodelingprep.com/image-stock/DDOG.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x27c99fBde9D0d2AA4f4Bfb4943f237843DdF6958",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "DELL",
            logo: "https://financialmodelingprep.com/image-stock/DELL.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x941AE714EC6D8130c7B75d67160Ca08f1e7d11Dd",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "ELF",
            logo: "https://financialmodelingprep.com/image-stock/ELF.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x39EC44Bee4F6A116c6F9B8De566848a985C53C60",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "EWY",
            logo: "https://financialmodelingprep.com/image-stock/EWY.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x7f0aBeF0C07280F82c6a08ead09dEd6BAE2C13Fc",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "F",
            logo: "https://financialmodelingprep.com/image-stock/F.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x25C288E6D899b9BC30160965aD9644c67e73bE0C",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "FLNC",
            logo: "https://financialmodelingprep.com/image-stock/FLNC.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x282e87451E10fA6679BC7D76C69BE44cD3fC777C",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "FUTU",
            logo: "https://financialmodelingprep.com/image-stock/FUTU.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xeB30663bDFf0622Ef4e4E5cBb4E975F19f33f51D",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "GLW",
            logo: "https://financialmodelingprep.com/image-stock/GLW.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x7c04E6A3368F2A1DE3874f0e80d2e0A1a9915da6",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "GME",
            logo: "https://financialmodelingprep.com/image-stock/GME.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x1b0E319c6A659F002271B69dB8A7df2F911c153E",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "GOOGL",
            logo: "https://financialmodelingprep.com/image-stock/GOOGL.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "INOD",
            logo: "https://financialmodelingprep.com/image-stock/INOD.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xf1953DAB6FaD537488d5A022361FfAa8B4c95eC6",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "INTC",
            logo: "https://financialmodelingprep.com/image-stock/INTC.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xc72b96e0E48ecd4DC75E1e45396e26300BC39681",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "INTU",
            logo: "https://financialmodelingprep.com/image-stock/INTU.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x56d23beE5f41A7120170b0c603Dae30128e460e9",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "IONQ",
            logo: "https://financialmodelingprep.com/image-stock/IONQ.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x558378E000D634A36593E338eBacdd6207640EfE",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "IREN",
            logo: "https://financialmodelingprep.com/image-stock/IREN.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xF0AB0c93bE6F41369d302e55db1A96b3c430212D",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "LITE",
            logo: "https://financialmodelingprep.com/image-stock/LITE.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x8eF20885F94e3D9bc7eB3080279188Bd5ED7c08C",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "LLY",
            logo: "https://financialmodelingprep.com/image-stock/LLY.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x8005d266423c7ea827372c9c864491e5786600ea",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "LULU",
            logo: "https://financialmodelingprep.com/image-stock/LULU.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x4e62068525Ab11FE768e29dfD00ef909B9803016",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "LUNR",
            logo: "https://financialmodelingprep.com/image-stock/LUNR.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xa5D4968421bA94814Be3B136b15cf422101aC1a3",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "MDB",
            logo: "https://financialmodelingprep.com/image-stock/MDB.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xDdf2266b79abf0B48898959B0ed6E6adf512be74",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "META",
            logo: "https://financialmodelingprep.com/image-stock/META.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "MRVL",
            logo: "https://financialmodelingprep.com/image-stock/MRVL.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x62fd0668e10D8B72339BE2DCF7643001688ff13B",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "MSFT",
            logo: "https://financialmodelingprep.com/image-stock/MSFT.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xe93237C50D904957Cf27E7B1133b510C669c2e74",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "MSTR",
            logo: "https://financialmodelingprep.com/image-stock/MSTR.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xec262a75e413fAfD0dF80480274532C79D42da09",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "MU",
            logo: "https://financialmodelingprep.com/image-stock/MU.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xfF080c8ce2E5feadaCa0Da81314Ae59D232d4afD",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "MXL",
            logo: "https://financialmodelingprep.com/image-stock/MXL.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x48961813349333209994750ffA89b3c5C22eC969",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "NBIS",
            logo: "https://financialmodelingprep.com/image-stock/NBIS.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x9D9c6684F596F66a64C030B93A886D51Fd4D7931",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "NFLX",
            logo: "https://financialmodelingprep.com/image-stock/NFLX.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xE0444EF8BF4eD74f74FD73686e2ddF4C1c5591E8",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "NNE",
            logo: "https://financialmodelingprep.com/image-stock/NNE.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xBEF75684C43c4ea7BD18Dd532a2244674Ee8b926",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "NOW",
            logo: "https://financialmodelingprep.com/image-stock/NOW.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x0C3260aF4B8f13a69c4c2dFb84fD667890CDFa14",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "NU",
            logo: "https://financialmodelingprep.com/image-stock/NU.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x408c14038a04f7bD235329E26d2bf569ee20e250",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "NVDA",
            logo: "https://financialmodelingprep.com/image-stock/NVDA.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "NVTS",
            logo: "https://financialmodelingprep.com/image-stock/NVTS.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xbE6702d7b70315376dC48a3293f24f0982F86386",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "ORCL",
            logo: "https://financialmodelingprep.com/image-stock/ORCL.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xb0992820E760d836549ba69BC7598b4af75dEE03",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "P",
            logo: "https://cdn.robinhood.com/ncw_assets/logos/0x1cdad396db64bda184d5182a97dd9b3c62100b7d.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x1Cdad396DB64BDa184d5182A97Dd9B3C62100b7D",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "PENG",
            logo: "https://financialmodelingprep.com/image-stock/PENG.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x9b23573b156B52565012F5cE02CDF60AFBaa70Be",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "PLTR",
            logo: "https://financialmodelingprep.com/image-stock/PLTR.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x894E1EC2D74FFE5AEF8Dc8A9e84686acCB964F2A",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "POET",
            logo: "https://financialmodelingprep.com/image-stock/POET.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xcf6B2D875361be807EAfa57458c80f28521F9333",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "PR",
            logo: "https://financialmodelingprep.com/image-stock/PR.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x4189F0c66EBBB0bfeF1C31f763131361EF32f77C",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "QBTS",
            logo: "https://financialmodelingprep.com/image-stock/QBTS.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xC583c60aeF9Dc401Da72cEC1B404743a93cea1Cc",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "QCOM",
            logo: "https://financialmodelingprep.com/image-stock/QCOM.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x0f17206447090e464C277571124dD2688E48AEA9",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "QQQ",
            logo: "https://financialmodelingprep.com/image-stock/QQQ.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xD5f3879160bc7c32ebb4dC785F8a4F505888de68",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "QUBT",
            logo: "https://financialmodelingprep.com/image-stock/QUBT.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x59818904ab4cE163b3cE4FfB64f2D6Ca02c434B4",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "RBLX",
            logo: "https://financialmodelingprep.com/image-stock/RBLX.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xF0C4BF4C582cb3836e98394b1d4e7B7281101bE8",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "RDDT",
            logo: "https://financialmodelingprep.com/image-stock/RDDT.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x05b37Fb53A299a1b874A619e1c4C404D52C36F4C",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "RDW",
            logo: "https://financialmodelingprep.com/image-stock/RDW.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x92Ef19E82bD8fF36661DE838D5eaE7e5CEF0EfFE",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "RGTI",
            logo: "https://financialmodelingprep.com/image-stock/RGTI.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x284358abc07F9359f19f4b5b4aC91901Be2597Ba",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "RIVN",
            logo: "https://financialmodelingprep.com/image-stock/RIVN.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xB1BF26c1D20ff267A4f93550d1E0d06ac40a114B",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "RKLB",
            logo: "https://financialmodelingprep.com/image-stock/RKLB.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x3b14C39E89D60D627b42a1A4CA45b5bb45Fc12e2",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "SATS",
            logo: "https://financialmodelingprep.com/image-stock/SATS.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x95052ddcd5DC25641657424A8Cf04834997E1730",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "SGOV",
            logo: "https://financialmodelingprep.com/image-stock/SGOV.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x92FD66527192E3e61d4DDd13322Aa222DE86F9B5",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "SHOP",
            logo: "https://financialmodelingprep.com/image-stock/SHOP.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xF53F66751B1Eff985311b693531E3290F600c410",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "SKHY",
            logo: "https://cdn.robinhood.com/ncw_assets/logos/0x84cab63bc87912e71ad199ff14a0ba45de68fef8.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x84CAb63bc87912E71ad199ff14A0bA45de68FeF8",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "SLV",
            logo: "https://financialmodelingprep.com/image-stock/SLV.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x411eFb0E7f985935DAec3D4C3ebaEa0d0AD7D89f",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "SMCI",
            logo: "https://financialmodelingprep.com/image-stock/SMCI.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xc01aA1fECeC0605b13bc84874ff7256C0f5F562a",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "SNDK",
            logo: "https://financialmodelingprep.com/image-stock/SNDK.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xB90A19fF0Af67f7779afF50A882A9CfF42446400",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "SOFI",
            logo: "https://financialmodelingprep.com/image-stock/SOFI.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x98E75885157C80992A8D41b696D8c9C6Fb30A926",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "SOXX",
            logo: "https://financialmodelingprep.com/image-stock/SOXX.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x75742c18BC1f1C5c5f448f4C9D9C6F66dafAAa38",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "SPCX",
            logo: "https://financialmodelingprep.com/image-stock/SPCX.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x4a0E65A3EcceC6dBe60AE065F2e7bb85Fae35eEa",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "SPMO",
            logo: "https://financialmodelingprep.com/image-stock/SPMO.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xAd622320e520de39e72d41EF07438C3Fd3354875",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "SPY",
            logo: "https://financialmodelingprep.com/image-stock/SPY.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x117cc2133c37B721F49dE2A7a74833232B3B4C0C",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "TSEM",
            logo: "https://cdn.robinhood.com/ncw_assets/logos/0x89776d4cd68193597a2fc132cfac1fde36ccea8a.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x89776d4Cd68193597A2fC132cfaC1fDe36CCeA8a",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "TSLA",
            logo: "https://financialmodelingprep.com/image-stock/TSLA.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x322F0929c4625eD5bAd873c95208D54E1c003b2d",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "TSM",
            logo: "https://financialmodelingprep.com/image-stock/TSM.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x58FfE4a942d3885bAa22D7520691F611EF09e7AA",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "TTWO",
            logo: "https://financialmodelingprep.com/image-stock/TTWO.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x5e81213613b6B86EaB4c6c50d718d34359459786",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "UMC",
            logo: "https://financialmodelingprep.com/image-stock/UMC.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x0E6e67Ba88e7b5d9B67636A215c76779B948dE79",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "UPS",
            logo: "https://financialmodelingprep.com/image-stock/UPS.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xf23250dac154D05Bb671CB0d0eBEf3c635c79CE2",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "USAR",
            logo: "https://financialmodelingprep.com/image-stock/USAR.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xd917B029C761D264c6A312BBbcDA868658eF86a6",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "USO",
            logo: "https://cdn.robinhood.com/ncw_assets/logos/0xa30fa36db767ad9ed3f7a60fc79526fb4d56d344.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xa30FA36Db767ad9eD3f7a60fC79526fB4d56D344",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "WDAY",
            logo: "https://financialmodelingprep.com/image-stock/WDAY.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x82DA4646242e1D962e96e932269Dc644c94a9CaA",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "XLK",
            logo: "https://financialmodelingprep.com/image-stock/XLK.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x15Cd20759CE7F3285c29A319dE2D1A2e098c6f43",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "XNDU",
            logo: "https://cdn.robinhood.com/ncw_assets/logos/0xa8eb3bccbf2017ee7cbfb652eb51cf2e1b153289.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xA8eB3BCcbf2017eE7CBfb652eB51CF2E1B153289",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "XOM",
            logo: "https://financialmodelingprep.com/image-stock/XOM.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0xf9B46d3D1B22199D4D1025a9cEDB540A33F1a2d5",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "ZM",
            logo: "https://financialmodelingprep.com/image-stock/ZM.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x44c4F142009036cF477eD2d09932051843137CF1",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .robinhood,
            ticker: "ZS",
            logo: "https://financialmodelingprep.com/image-stock/ZS.png",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x7dc013eB55e436f30d7ED1AFE4E36d6e45e3c3f7",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .sei,
            ticker: "SEI",
            logo: "sei",
            decimals: 18,
            priceProviderId: "sei-network",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "ARB",
            logo: "arbitrum",
            decimals: 18,
            priceProviderId: "arbitrum",
            contractAddress: "0x912CE59144191C1204E64559FE8253a0e49E6548",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "WETH",
            logo: "wETH",
            decimals: 18,
            priceProviderId: "weth",
            contractAddress: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "DAI",
            logo: "dai",
            decimals: 18,
            priceProviderId: "DAI",
            contractAddress: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "USDS",
            logo: "usds",
            decimals: 18,
            priceProviderId: "usds",
            contractAddress: "0x6491c05A82219b8D1479057361ff1654749b876b",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "FOX",
            logo: "fox",
            decimals: 18,
            priceProviderId: "shapeshift-fox-token",
            contractAddress: "0xf929de51D91C77E42f5090069E0AD7A09e513c73",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "GRT",
            logo: "grt",
            decimals: 18,
            priceProviderId: "GRT",
            contractAddress: "0x9623063377AD1B27544C965cCd7342f7EA7e88C7",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "LDO",
            logo: "ldo",
            decimals: 18,
            priceProviderId: "LDO",
            contractAddress: "0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "LINK",
            logo: "link",
            decimals: 18,
            priceProviderId: "chainlink",
            contractAddress: "0xf97f4df75117a78c1A5a0DBb814Af92458539FB4",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "PEPE",
            logo: "pepe",
            decimals: 18,
            priceProviderId: "PEPE",
            contractAddress: "0x25d887Ce7a35172C62FeBFD67a1856F20FaEbB00",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "PYTH",
            logo: "pyth",
            decimals: 6,
            priceProviderId: "pyth-network",
            contractAddress: "0xE4D5c6aE46ADFAF04313081e8C0052A30b6Dd724",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "TGT",
            logo: "tgt",
            decimals: 18,
            priceProviderId: "thorwallet",
            contractAddress: "0x429fEd88f10285E61b12BDF00848315fbDfCC341",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "UNI",
            logo: "uni",
            decimals: 18,
            priceProviderId: "UNI",
            contractAddress: "0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "USDC.e",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin-ethereum-bridged",
            contractAddress: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "USD₮0",
            logo: "usdt",
            decimals: 6,
            priceProviderId: "tether",
            contractAddress: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "WBTC",
            logo: "wbtc",
            decimals: 8,
            priceProviderId: "wrapped-bitcoin",
            contractAddress: "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .arbitrum,
            ticker: "ezETH",
            logo: "ezeth",
            decimals: 18,
            priceProviderId: "ezETH",
            contractAddress: "0x2416092f143378750bb29b79eD961ab195CcEea5",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .avalanche,
            ticker: "AVAX",
            logo: "avax",
            decimals: 18,
            priceProviderId: "avalanche-2",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .avalanche,
            ticker: "BLS",
            logo: "bls",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x46B9144771Cb3195D66e4EDA643a7493fADCAF9D",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .avalanche,
            ticker: "BTC.b",
            logo: "btc",
            decimals: 8,
            priceProviderId: "wrapped-bitcoin",
            contractAddress: "0x152b9d0FdC40C096757F570A51E494bd4b943E50",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .avalanche,
            ticker: "COQ",
            logo: "coq",
            decimals: 18,
            priceProviderId: "coq-inu",
            contractAddress: "0x420FcA0121DC28039145009570975747295f2329",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .avalanche,
            ticker: "JOE",
            logo: "joe",
            decimals: 18,
            priceProviderId: "joe",
            contractAddress: "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .avalanche,
            ticker: "PNG",
            logo: "PNG",
            decimals: 18,
            priceProviderId: "pangolin",
            contractAddress: "0x60781C2586D68229fde47564546784ab3fACA982",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .avalanche,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .avalanche,
            ticker: "USDT",
            logo: "usdt",
            decimals: 6,
            priceProviderId: "tether",
            contractAddress: "0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .avalanche,
            ticker: "WAVAX",
            logo: "avax",
            decimals: 18,
            priceProviderId: "avalanche-2",
            contractAddress: "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .avalanche,
            ticker: "aAvaUSDC",
            logo: "aave",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0x625E7708f30cA75bfd92586e17077590C60eb4cD",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .avalanche,
            ticker: "sAVAX",
            logo: "savax",
            decimals: 18,
            priceProviderId: "benqi-liquid-staked-avax",
            contractAddress: "0x2b2C81e08f1Af8835a78Bb2A90AE924ACE0eA4bE",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .base,
            ticker: "AERO",
            logo: "aero",
            decimals: 18,
            priceProviderId: "aerodrome-finance",
            contractAddress: "0x940181a94A35A4569E4529A3CDfB74e38FD98631",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .base,
            ticker: "DAI",
            logo: "dai",
            decimals: 18,
            priceProviderId: "dai",
            contractAddress: "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .base,
            ticker: "USDS",
            logo: "usds",
            decimals: 18,
            priceProviderId: "usds",
            contractAddress: "0x820C137fa70C8691f0e44dC420a5e53c168921Dc",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .base,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .base,
            ticker: "OM",
            logo: "om",
            decimals: 18,
            priceProviderId: "mantra-dao",
            contractAddress: "0x3992B27dA26848C2b19CeA6Fd25ad5568B68AB98",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .base,
            ticker: "PYTH",
            logo: "pyth",
            decimals: 6,
            priceProviderId: "pyth-network",
            contractAddress: "0x4c5d8A75F3762c1561D96f177694f67378705E98",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .base,
            ticker: "SNX",
            logo: "snx",
            decimals: 18,
            priceProviderId: "havven",
            contractAddress: "0x22e6966B799c4D5B13BE962E1D117b56327FDa66",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .base,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .base,
            ticker: "W",
            logo: "w",
            decimals: 18,
            priceProviderId: "w",
            contractAddress: "0xB0fFa8000886e57F86dd5264b9582b2Ad87b2b91",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .base,
            ticker: "WEWE",
            logo: "wewe",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x6b9bb36519538e0C073894E964E90172E1c0B41F",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .base,
            ticker: "cbETH",
            logo: "cbeth",
            decimals: 18,
            priceProviderId: "cbETH",
            contractAddress: "0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .base,
            ticker: "ezETH",
            logo: "ezeth",
            decimals: 18,
            priceProviderId: "ezETH",
            contractAddress: "0x2416092f143378750bb29b79eD961ab195CcEea5",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .base,
            ticker: "rETH",
            logo: "reth",
            decimals: 18,
            priceProviderId: "reth",
            contractAddress: "0xB6fe221Fe9EeF5aBa221c348bA20A1Bf5e73624c",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "btc",
            decimals: 8,
            priceProviderId: "bitcoin",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .zcash,
            ticker: "ZEC",
            logo: "zec",
            decimals: 8,
            priceProviderId: "zcash",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .mantle,
            ticker: "MNT",
            logo: "mantle",
            decimals: 18,
            priceProviderId: "mantle",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .bitcoinCash,
            ticker: "BCH",
            logo: "bch",
            decimals: 8,
            priceProviderId: "bitcoin-cash",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .cardano,
            ticker: "ADA",
            logo: "ada",
            decimals: 6,
            priceProviderId: "cardano",
            contractAddress: "",
            isNativeToken: true
        ),
        // Top 10 Cardano native tokens (CNT). The `contractAddress` is the
        // dot-separated CardanoAssetId form: `<policyId>.<asset_name_hex>` —
        // see `Blockchain/Cardano/Models/CardanoAssetId.swift`. The asset_name
        // hex decodes to the ticker ASCII for most entries; USDM and DJED
        // carry CIP-67 (label 333) binary prefixes (`0014df10…`).
        CoinMeta(
            chain: .cardano,
            ticker: "USDM",
            logo: "usdm",
            decimals: 6,
            priceProviderId: "usdm-2",
            contractAddress: "c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad.0014df105553444d",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .cardano,
            ticker: "iUSD",
            logo: "iusd",
            decimals: 6,
            priceProviderId: "iusd",
            contractAddress: "f66d78b4a3cb3d37afa0ec36461e51ecbde00f26c8f0a68f94b69880.69555344",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .cardano,
            ticker: "DJED",
            logo: "djed",
            decimals: 6,
            priceProviderId: "djed",
            contractAddress: "8db269c3ec630e06ae29f74bc39edd1f87c819f1056206e879a1cd61.446a65644d6963726f555344",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .cardano,
            ticker: "LQ",
            logo: "lq",
            decimals: 6,
            priceProviderId: "liqwid-finance",
            contractAddress: "da8c30857834c6ae7203935b89278c532b3995245295456f993e1d24.4c51",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .cardano,
            ticker: "MIN",
            logo: "min",
            decimals: 6,
            priceProviderId: "minswap",
            contractAddress: "29d222ce763455e3d7a09a665ce554f00ac89d2e99a1a83d267170c6.4d494e",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .cardano,
            ticker: "SNEK",
            logo: "snek",
            decimals: 0,
            priceProviderId: "snek",
            contractAddress: "279c909f348e533da5808898f87f9a14bb2c3dfbbacccd631d927a3f.534e454b",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .cardano,
            ticker: "SUNDAE",
            logo: "sundae",
            decimals: 6,
            priceProviderId: "sundaeswap",
            contractAddress: "9a9693a9a37912a5097918f97918d15240c92ab729a0b7c4aa144d77.53554e444145",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .cardano,
            ticker: "IAG",
            logo: "iag",
            decimals: 6,
            priceProviderId: "iagon",
            contractAddress: "5d16cc1a177b5d9ba9cfa9793b07e60f1fb70fea1f8aef064415d114.494147",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .cardano,
            ticker: "HOSKY",
            logo: "hosky",
            decimals: 0,
            priceProviderId: "hosky",
            contractAddress: "a0028f350aaabe0545fdcb56b039bfb08e4bb4d8c4d7c3c7d481c235.484f534b59",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .cardano,
            ticker: "WMTX",
            logo: "wmtx",
            decimals: 6,
            priceProviderId: "world-mobile-token",
            contractAddress: "e5a42a1a1d3d1da71b0449663c32798725888d2eb0843c4dabeca05a.576f726c644d6f62696c65546f6b656e58",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .blast,
            ticker: "AI",
            logo: "anyinu",
            decimals: 18,
            priceProviderId: "any-inu",
            contractAddress: "0x764933fbAd8f5D04Ccd088602096655c2ED9879F",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .blast,
            ticker: "BAG",
            logo: "bag",
            decimals: 18,
            priceProviderId: "bag",
            contractAddress: "0xb9dfCd4CF589bB8090569cb52FaC1b88Dbe4981F",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .blast,
            ticker: "BLAST",
            logo: "blast",
            decimals: 18,
            priceProviderId: "blast",
            contractAddress: "0xb1a5700fA2358173Fe465e6eA4Ff52E36e88E2ad",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .blast,
            ticker: "DACKIE",
            logo: "dackie",
            decimals: 18,
            priceProviderId: "dackieswap",
            contractAddress: "0x47C337Bd5b9344a6F3D6f58C474D9D8cd419D8cA",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .blast,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .blast,
            ticker: "JUICE",
            logo: "juice",
            decimals: 18,
            priceProviderId: "juice-finance",
            contractAddress: "0x818a92bc81Aad0053d72ba753fb5Bc3d0C5C0923",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .blast,
            ticker: "MIM",
            logo: "mim",
            decimals: 18,
            priceProviderId: "magic-internet-money-blast",
            contractAddress: "0x76DA31D7C9CbEAE102aff34D3398bC450c8374c1",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .blast,
            ticker: "OMNI",
            logo: "omni",
            decimals: 18,
            priceProviderId: "omnicat",
            contractAddress: "0x9e20461bc2c4c980f62f1B279D71734207a6A356",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .blast,
            ticker: "USDB",
            logo: "usdb",
            decimals: 18,
            priceProviderId: "usdb",
            contractAddress: "0x4300000000000000000000000000000000000003",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .blast,
            ticker: "WBTC",
            logo: "wbtc",
            decimals: 8,
            priceProviderId: "wrapped-bitcoin",
            contractAddress: "0xF7bc58b8D8f97ADC129cfC4c9f45Ce3C0E1D2692",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .blast,
            ticker: "WETH",
            logo: "weth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "0x4300000000000000000000000000000000000004",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .blast,
            ticker: "ZERO",
            logo: "zero",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x357f93E17FdabEcd3fEFc488a2d27dff8065d00f",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .blast,
            ticker: "bLOOKS",
            logo: "blooks",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "0x406F10d635be12ad33D6B133C6DA89180f5B999e",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .bscChain,
            ticker: "AAVE",
            logo: "aave",
            decimals: 18,
            priceProviderId: "aave",
            contractAddress: "0xfb6115445bff7b52feb98650c87f44907e58f802",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .bscChain,
            ticker: "BNB",
            logo: "bsc",
            decimals: 18,
            priceProviderId: "binancecoin",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .bscChain,
            ticker: "COMP",
            logo: "comp",
            decimals: 18,
            priceProviderId: "compound-governance-token",
            contractAddress: "0x52ce071bd9b1c4b00a0b92d298c512478cad67e8",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .bscChain,
            ticker: "DAI",
            logo: "dai",
            decimals: 18,
            priceProviderId: "dai",
            contractAddress: "0x1af3f329e8be154074d8769d1ffa4ee058b1dbc3",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .bscChain,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "0x2170ed0880ac9a755fd29b2688956bd959f933f8",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .bscChain,
            ticker: "KNC",
            logo: "knc",
            decimals: 18,
            priceProviderId: "kyber-network-crystal",
            contractAddress: "0xfe56d5892bdffc7bf58f2e84be1b2c32d21c308b",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .bscChain,
            ticker: "PEPE",
            logo: "pepe",
            decimals: 18,
            priceProviderId: "pepe",
            contractAddress: "0x25d887ce7a35172c62febfd67a1856f20faebb00",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .bscChain,
            ticker: "SUSHI",
            logo: "sushi",
            decimals: 18,
            priceProviderId: "sushi",
            contractAddress: "0x947950bcc74888a40ffa2593c5798f11fc9124c4",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .bscChain,
            ticker: "USDC",
            logo: "usdc",
            decimals: 18,
            priceProviderId: "usd-coin",
            contractAddress: "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .bscChain,
            ticker: "USDT",
            logo: "usdt",
            decimals: 18,
            priceProviderId: "tether",
            contractAddress: "0x55d398326f99059fF775485246999027B3197955",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .cronosChain,
            ticker: "CRO",
            logo: "cro",
            decimals: 18,
            priceProviderId: "crypto-com-chain",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .dash,
            ticker: "DASH",
            logo: "dash",
            decimals: 8,
            priceProviderId: "dash",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .dogecoin,
            ticker: "DOGE",
            logo: "doge",
            decimals: 8,
            priceProviderId: "dogecoin",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .dydx,
            ticker: "DYDX",
            logo: "dydx",
            decimals: 18,
            priceProviderId: "dydx-chain",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "AAVE",
            logo: "aave",
            decimals: 18,
            priceProviderId: "aave",
            contractAddress: "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "BAL",
            logo: "bal",
            decimals: 18,
            priceProviderId: "balancer",
            contractAddress: "0xba100000625a3754423978a60c9317c58a424e3d",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "BAT",
            logo: "bat",
            decimals: 18,
            priceProviderId: "basic-attention-token",
            contractAddress: "0x0d8775f648430679a709e98d2b0cb6250d2887ef",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "COMP",
            logo: "comp",
            decimals: 18,
            priceProviderId: "compound-governance-token",
            contractAddress: "0xc00e94cb662c3520282e6f5717214004a7f26888",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "DAI",
            logo: "dai",
            decimals: 18,
            priceProviderId: "dai",
            contractAddress: "0x6b175474e89094c44da98b954eedeac495271d0f",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "USDS",
            logo: "usds",
            decimals: 18,
            priceProviderId: "usds",
            contractAddress: "0xdC035D45d973E3EC169d2276DDab16f1e407384F",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "FLIP",
            logo: "flip",
            decimals: 18,
            priceProviderId: "chainflip",
            contractAddress: "0x826180541412d574cf1336d22c0c0a287822678a",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "FOX",
            logo: "fox",
            decimals: 18,
            priceProviderId: "shapeshift-fox-token",
            contractAddress: "0xc770eefad204b5180df6a14ee197d99d808ee52d",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "GRT",
            logo: "grt",
            decimals: 18,
            priceProviderId: "the-graph",
            contractAddress: "0xc944e90c64b2c07662a292be6244bdf05cda44a7",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "KNC",
            logo: "knc",
            decimals: 18,
            priceProviderId: "kyber-network-crystal",
            contractAddress: "0xdefa4e8a7bcba345f687a2f1456f5edd9ce97202",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "LINK",
            logo: "link",
            decimals: 18,
            priceProviderId: "chainlink",
            contractAddress: "0x514910771af9ca656af840dff83e8264ecf986ca",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "MATIC",
            logo: "matic",
            decimals: 18,
            priceProviderId: "matic-network",
            contractAddress: "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "MKR",
            logo: "mkr",
            decimals: 18,
            priceProviderId: "maker",
            contractAddress: "0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "PEPE",
            logo: "pepe",
            decimals: 18,
            priceProviderId: "pepe",
            contractAddress: "0x6982508145454ce325ddbe47a25d4ec3d2311933",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "POL",
            logo: "pol",
            decimals: 18,
            priceProviderId: "polygon-ecosystem-token",
            contractAddress: "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "SNX",
            logo: "snx",
            decimals: 18,
            priceProviderId: "havven",
            contractAddress: "0xc011a73ee8576fb46f5e1c5751ca3b9fe0af2a6f",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "SUSHI",
            logo: "sushi",
            decimals: 18,
            priceProviderId: "sushi",
            contractAddress: "0x6b3595068778dd592e39a122f4f5a5cf09c90fe2",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "TGT",
            logo: "tgt",
            decimals: 18,
            priceProviderId: "thorwallet",
            contractAddress: "0x108a850856Db3f85d0269a2693D896B394C80325",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "UNI",
            logo: "uni",
            decimals: 18,
            priceProviderId: "uniswap",
            contractAddress: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984",
            isNativeToken: false
        ),
        ethUSDC,
        CoinMeta(
            chain: .ethereum,
            ticker: "USDT",
            logo: "usdt",
            decimals: 6,
            priceProviderId: "tether",
            contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "VULT",
            logo: "vult",
            decimals: 18,
            priceProviderId: "vultisig",
            contractAddress: "0xb788144DF611029C60b859DF47e79B7726C4DEBa",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "WBTC",
            logo: "wbtc",
            decimals: 8,
            priceProviderId: "wrapped-bitcoin",
            contractAddress: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "WETH",
            logo: "weth",
            decimals: 18,
            priceProviderId: "weth",
            contractAddress: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .ethereum,
            ticker: "YFI",
            logo: "yfi",
            decimals: 18,
            priceProviderId: "yearn-finance",
            contractAddress: "0x0bc529c00c6401aef6d220be8c6ea1667f6ad93e",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .gaiaChain,
            ticker: "ATOM",
            logo: "atom",
            decimals: 6,
            priceProviderId: "cosmos",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .gaiaChain,
            ticker: "FUZN",
            logo: "fuzn",
            decimals: 6,
            priceProviderId: "fuzion",
            contractAddress: "ibc/6BBBB4B63C51648E9B8567F34505A9D5D8BAAC4C31D768971998BE8C18431C26",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .gaiaChain,
            ticker: "KUJI",
            logo: "kuji",
            decimals: 6,
            priceProviderId: "kujira",
            contractAddress: "ibc/4CC44260793F84006656DD868E017578F827A492978161DA31D7572BCB3F4289",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .gaiaChain,
            ticker: "LVN",
            logo: "levana",
            decimals: 6,
            priceProviderId: "levana-protocol",
            contractAddress: "ibc/6C95083ADD352D5D47FB4BA427015796E5FEF17A829463AD05ECD392EB38D889",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .gaiaChain,
            ticker: "NAMI",
            logo: "nami",
            decimals: 6,
            priceProviderId: "nami-protocol",
            contractAddress: "ibc/4622E82B845FFC6AA8B45C1EB2F507133A9E876A5FEA1BA64585D5F564405453",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .gaiaChain,
            ticker: "NSTK",
            logo: "nstk",
            decimals: 6,
            priceProviderId: "unstake-fi",
            contractAddress: "ibc/0B99C4EFF1BD05E56DEDEE1D88286DB79680C893724E0E7573BC369D79B5DDF3",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .gaiaChain,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "ibc/F663521BF1836B00F5F177680F74BFB9A8B5654A694D0D2BC249E03CF2509013",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .gaiaChain,
            ticker: "USK",
            logo: "usk",
            decimals: 6,
            priceProviderId: "usk",
            contractAddress: "ibc/A47E814B0E8AE12D044637BCB4576FCA675EF66300864873FA712E1B28492B78",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .gaiaChain,
            ticker: "WINK",
            logo: "wink",
            decimals: 6,
            priceProviderId: "winkhub",
            contractAddress: "ibc/4363FD2EF60A7090E405B79A6C4337C5E9447062972028F5A99FB041B9571942",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .gaiaChain,
            ticker: "rKUJI",
            logo: "rkuji",
            decimals: 6,
            priceProviderId: "kujira",
            contractAddress: "ibc/50A69DC508ACCADE2DAC4B8B09AA6D9C9062FCBFA72BB4C6334367DECD972B06",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "ASTRO",
            logo: "terra-astroport",
            decimals: 6,
            priceProviderId: "astroport-fi",
            contractAddress: "ibc/640E1C3E28FD45F611971DF891AE3DC90C825DF759DF8FAA8F33F7F72B35AD56",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "FUZN",
            logo: "fuzion",
            decimals: 6,
            priceProviderId: "fuzion",
            contractAddress: "factory/kujira1sc6a0347cc5q3k890jj0pf3ylx2s38rh4sza4t/ufuzn",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "KUJI",
            logo: "kuji",
            decimals: 6,
            priceProviderId: "kujira",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "LUNC",
            logo: "lunc",
            decimals: 6,
            priceProviderId: "terra-luna",
            contractAddress: "ibc/119334C55720942481F458C9C462F5C0CD1F1E7EEAC4679D674AA67221916AEA",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "MNTA",
            logo: "mnta",
            decimals: 6,
            priceProviderId: "mantadao",
            contractAddress: "factory/kujira1643jxg8wasy5cfcn7xm8rd742yeazcksqlg4d7/umnta",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "NAMI",
            logo: "nami",
            decimals: 6,
            priceProviderId: "nami-protocol",
            contractAddress: "factory/kujira13x2l25mpkhwnwcwdzzd34cr8fyht9jlj7xu9g4uffe36g3fmln8qkvm3qn/unami",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "NSTK",
            logo: "nstk",
            decimals: 6,
            priceProviderId: "unstake-fi",
            contractAddress: "factory/kujira1aaudpfr9y23lt9d45hrmskphpdfaq9ajxd3ukh/unstk",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "ibc/FE98AAD68F02F03565E9FA39A5E627946699B2B07115889ED812D8BA639576A9",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "USK",
            logo: "usk",
            decimals: 6,
            priceProviderId: "usk",
            contractAddress: "factory/kujira1qk00h5atutpsv900x202pxx42npjr9thg58dnqpa72f2p7m2luase444a7/uusk",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "WINK",
            logo: "wink",
            decimals: 6,
            priceProviderId: "winkhub",
            contractAddress: "factory/kujira12cjjeytrqcj25uv349thltcygnp9k0kukpct0e/uwink",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "rKUJI",
            logo: "rkuji",
            decimals: 6,
            priceProviderId: "kujira",
            contractAddress: "factory/kujira1tsekaqv9vmem0zwskmf90gpf0twl6k57e8vdnq/urkuji",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "LVN",
            logo: "levana",
            decimals: 6,
            priceProviderId: "levana-protocol",
            contractAddress: "ibc/B64A07C006C0F5E260A8AD50BD53568F1FD4A0D75B7A9F8765C81BEAFDA62053",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .kujira,
            ticker: "AUTO",
            logo: "auto-token-kujira",
            decimals: 6,
            priceProviderId: "auto-2",
            contractAddress: "factory/kujira13x2l25mpkhwnwcwdzzd34cr8fyht9jlj7xu9g4uffe36g3fmln8qkvm3qn/uauto",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .litecoin,
            ticker: "LTC",
            logo: "ltc",
            decimals: 8,
            priceProviderId: "litecoin",
            contractAddress: "",
            isNativeToken: true
        ),
        cacao,
        CoinMeta(
            chain: .mayaChain,
            ticker: "MAYA",
            logo: "maya",
            decimals: 4,
            priceProviderId: "",
            contractAddress: "maya",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .mayaChain,
            ticker: "AZTEC",
            logo: "aztec",
            decimals: 4,
            priceProviderId: "",
            contractAddress: "aztec",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .noble,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .optimism,
            ticker: "DAI",
            logo: "dai",
            decimals: 18,
            priceProviderId: "dai",
            contractAddress: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .optimism,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .optimism,
            ticker: "FOX",
            logo: "fox",
            decimals: 18,
            priceProviderId: "shapeshift-fox-token",
            contractAddress: "0xf1a0da3367bc7aa04f8d94ba57b862ff37ced174",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .optimism,
            ticker: "LDO",
            logo: "ldo",
            decimals: 18,
            priceProviderId: "LDO",
            contractAddress: "0xFdb794692724153d1488CcdBE0C56c252596735F",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .optimism,
            ticker: "LINK",
            logo: "link",
            decimals: 18,
            priceProviderId: "chainlink",
            contractAddress: "0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .optimism,
            ticker: "OP",
            logo: "optimism",
            decimals: 18,
            priceProviderId: "optimism",
            contractAddress: "0x4200000000000000000000000000000000000042",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .optimism,
            ticker: "PYTH",
            logo: "pyth",
            decimals: 6,
            priceProviderId: "pyth-network",
            contractAddress: "0x99C59ACeBFEF3BBFB7129DC90D1a11DB0E91187f",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .optimism,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .optimism,
            ticker: "USDC.e",
            logo: "USDC.e",
            decimals: 6,
            priceProviderId: "usd-coin-ethereum-bridged",
            contractAddress: "0x7F5c764cBc14f9669B88837ca1490cCa17c31607",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .optimism,
            ticker: "USDT",
            logo: "usdt",
            decimals: 6,
            priceProviderId: "tether",
            contractAddress: "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .optimism,
            ticker: "WBTC",
            logo: "wbtc",
            decimals: 8,
            priceProviderId: "wrapped-bitcoin",
            contractAddress: "0x68f180fcCe6836688e9084f035309E29Bf0A2095",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .optimism,
            ticker: "ezETH",
            logo: "ezeth",
            decimals: 18,
            priceProviderId: "ezETH",
            contractAddress: "0x2416092f143378750bb29b79eD961ab195CcEea5",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .osmosis,
            ticker: "ION",
            logo: "ion",
            decimals: 6,
            priceProviderId: "ion",
            contractAddress: "uion",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .osmosis,
            ticker: "LVN",
            logo: "levana",
            decimals: 6,
            priceProviderId: "levana-protocol",
            contractAddress: "factory/osmo1mlng7pz4pnyxtpq0akfwall37czyk9lukaucsrn30ameplhhshtqdvfm5c/ulvn",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .osmosis,
            ticker: "OSMO",
            logo: "osmo",
            decimals: 6,
            priceProviderId: "osmosis",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .osmosis,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "ibc/498A0751C798A0D9A389AA3691123DADA57DAA4FE165D5C75894505B876BA6E4",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .osmosis,
            ticker: "USDC.eth.axl",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "ibc/D189335C6E4A68B513C10AB227BF1C1D38C746766278BA3EEB4FB14124F1D858",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .osmosis,
            ticker: "KUJI",
            logo: "kuji",
            decimals: 6,
            priceProviderId: "kujira",
            contractAddress: "ibc/93B87B73E634D3BD3CD782F52C99883F340CE6027F37718E0E04D552272DA8A9",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .polkadot,
            ticker: "DOT",
            logo: "dot",
            decimals: 10,
            priceProviderId: "polkadot",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .bittensor,
            ticker: "TAO",
            logo: "bittensor",
            decimals: 9,
            priceProviderId: "bittensor",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "AVAX",
            logo: "avax",
            decimals: 18,
            priceProviderId: "avalanche-2",
            contractAddress: "0x2C89bbc92BD86F8075d1DEcc58C7F4E0107f286b",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "BNB",
            logo: "bsc",
            decimals: 18,
            priceProviderId: "binancecoin",
            contractAddress: "0x3BA4c387f786bFEE076A58914F5Bd38d668B42c3",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "BUSD",
            logo: "busd",
            decimals: 18,
            priceProviderId: "binance-peg-busd",
            contractAddress: "0xdAb529f40E671A1D4bF91361c21bf9f0C9712ab7",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "FOX",
            logo: "fox",
            decimals: 18,
            priceProviderId: "shapeshift-fox-token",
            contractAddress: "0x65a05db8322701724c197af82c9cae41195b0aa8",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "LINK",
            logo: "link",
            decimals: 18,
            priceProviderId: "chainlink",
            contractAddress: "0xb0897686c545045aFc77CF20eC7A532E3120E0F1",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "POL",
            logo: "pol",
            decimals: 18,
            priceProviderId: "polygon-ecosystem-token",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "SHIB",
            logo: "shib",
            decimals: 18,
            priceProviderId: "shiba-inu",
            contractAddress: "0x6f8a06447Ff6FcF75d803135a7de15CE88C1d4ec",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "SOL",
            logo: "sol",
            decimals: 9,
            priceProviderId: "solana",
            contractAddress: "0xd93f7E271cB87c23AaA73edC008A79646d1F9912",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "USDC.e",
            logo: "USDC.e",
            decimals: 6,
            priceProviderId: "usd-coin-ethereum-bridged",
            contractAddress: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "USDT",
            logo: "usdt",
            decimals: 6,
            priceProviderId: "tether",
            contractAddress: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "WBTC",
            logo: "wbtc",
            decimals: 8,
            priceProviderId: "wrapped-bitcoin",
            contractAddress: "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .polygon,
            ticker: "WETH",
            logo: "weth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .qbtc,
            ticker: "QBTC",
            logo: "qbtc",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .ripple,
            ticker: "XRP",
            logo: "xrp",
            decimals: 6,
            priceProviderId: "ripple",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .solana,
            ticker: "JUP",
            logo: "jupiter",
            decimals: 6,
            priceProviderId: "jupiter-exchange-solana",
            contractAddress: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .solana,
            ticker: "KWEEN",
            logo: "kween",
            decimals: 6,
            priceProviderId: "kween",
            contractAddress: "DEf93bSt8dx58gDFCcz4CwbjYZzjwaRBYAciJYLfdCA9",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .solana,
            ticker: "PYTH",
            logo: "pyth",
            decimals: 6,
            priceProviderId: "pyth-network",
            contractAddress: "HZ1JovNiVvGrGNiiYvEozEVgZ58xaU3RKwX8eACQBCt3",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .solana,
            ticker: "RAY",
            logo: "raydium-ray-seeklogo-2",
            decimals: 6,
            priceProviderId: "raydium",
            contractAddress: "4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .solana,
            ticker: "SOL",
            logo: "solana",
            decimals: 9,
            priceProviderId: "solana",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .solana,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .solana,
            ticker: "USDT",
            logo: "usdt",
            decimals: 6,
            priceProviderId: "tether",
            contractAddress: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .solana,
            ticker: "USDS",
            logo: "usds",
            decimals: 6,
            priceProviderId: "usds",
            contractAddress: "USDSwr9ApdHk5bvJKMjzff41FfuX8bSxdKcR81vTwcA",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .solana,
            ticker: "WIF",
            logo: "dogwifhat-wif-logo",
            decimals: 6,
            priceProviderId: "dogwifcoin",
            contractAddress: "EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .sui,
            ticker: "ETH",
            logo: "eth",
            decimals: 8,
            priceProviderId: "ethereum",
            contractAddress: "0xd0e89b2af5e4910726fbcd8b8dd37bb79b29e5f83f7491bca830e94f7f226d29::eth::ETH",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .sui,
            ticker: "SUI",
            logo: "sui",
            decimals: 9,
            priceProviderId: "sui",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .sui,
            ticker: "DEEP",
            logo: "https://s2.coinmarketcap.com/static/img/coins/64x64/33391.png",
            decimals: 6,
            priceProviderId: "deep",
            contractAddress: "0xdeeb7a4662eec9f2f3def03fb937a663dddaa2e215b8078a284d026b7946c270::deep::DEEP",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .sui,
            ticker: "WAL",
            logo: "https://coin-images.coingecko.com/coins/images/54914/large/WAL_logo.png",
            decimals: 9,
            priceProviderId: "walrus-2",
            contractAddress: "0x356a26eb9e012a68958082340d4c4116e7f55615cf27affcff209cf0ae544f59::wal::WAL",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .sui,
            ticker: "CETUS",
            logo: "https://raw.githubusercontent.com/cosmostation/chainlist/main/chain/sui/asset/cetus.png",
            decimals: 9,
            priceProviderId: "cetus-protocol",
            contractAddress: "0x06864a6f921804860930db6ddbe2e16acdf8504495ea7481637a1c8b9a8fe54b::cetus::CETUS",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .sui,
            ticker: "NAVX",
            logo: "https://raw.githubusercontent.com/cosmostation/chainlist/main/chain/sui/asset/navx.png",
            decimals: 9,
            priceProviderId: "navi",
            contractAddress: "0xa99b8952d4f7d947ea77fe0ecdcc9e5fc0bcab2841d6e2a5aa00c3044e5544b5::navx::NAVX",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .sui,
            ticker: "BLUE",
            logo: "https://coin-images.coingecko.com/coins/images/30883/large/BLUE_200x200.png",
            decimals: 9,
            priceProviderId: "bluefin",
            contractAddress: "0xe1b45a0e641b9955a20aa0ad1c1f4ad86aad8afb07296d4085e349a50e90bdca::blue::BLUE",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .sui,
            ticker: "SEND",
            logo: "https://coin-images.coingecko.com/coins/images/50989/large/SEND.png",
            decimals: 9,
            priceProviderId: "suilend",
            contractAddress: "0xb45fcfcc2cc07ce0702cc2d229621e046c906ef14d9b25e8e4d25f6e8763fef7::send::SEND",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .sui,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .sui,
            ticker: "AXOL",
            logo: "https://coin-images.coingecko.com/coins/images/50412/large/AXOL.png",
            decimals: 9,
            priceProviderId: "axol",
            contractAddress: "0xf00eb7ab086967a33c04a853ad960e5c6b0955ef5a47d50b376d83856dc1215e::axol::AXOL",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .sui,
            ticker: "LOFI",
            logo: "https://s2.coinmarketcap.com/static/img/coins/64x64/34187.png",
            decimals: 9,
            priceProviderId: "lofi-2",
            contractAddress: "0xf22da9a24ad027cccb5f2d496cbe91de953d363513db08a3a734d361c7c17503::LOFI::LOFI",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .terra,
            ticker: "ASTRO",
            logo: "terra-astroport",
            decimals: 6,
            priceProviderId: "astroport-fi",
            contractAddress: "terra1nsuqsk6kh58ulczatwev87ttq2z6r3pusulg9r24mfj2fvtzd4uq3exn26",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .terra,
            ticker: "ASTRO-IBC",
            logo: "terra-astroport",
            decimals: 6,
            priceProviderId: "astroport-fi",
            contractAddress: "ibc/8D8A7F7253615E5F76CB6252A1E1BD921D5EDB7BBAAF8913FB1C77FF125D9995",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .terra,
            ticker: "LUNA",
            logo: "luna",
            decimals: 6,
            priceProviderId: "terra-luna-2",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .terra,
            ticker: "TPT",
            logo: "terra-poker-token",
            decimals: 6,
            priceProviderId: "tpt",
            contractAddress: "terra13j2k5rfkg0qhk58vz63cze0uze4hwswlrfnm0fa4rnyggjyfrcnqcrs5z2",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .terraClassic,
            ticker: "ASTROC",
            logo: "terra-astroport",
            decimals: 6,
            priceProviderId: "astroport",
            contractAddress: "terra1xj49zyqrwpv5k928jwfpfy2ha668nwdgkwlrg3",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .terraClassic,
            ticker: "LUNC",
            logo: "lunc",
            decimals: 6,
            priceProviderId: "terra-luna",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .terraClassic,
            ticker: "USTC",
            logo: "ustc",
            decimals: 6,
            priceProviderId: "terrausd",
            contractAddress: "uusd",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .terraClassic,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "ibc/0BB9D8513E8E8E9AE6A9D211D9136E6DA42288DDE6CFAA453A150A4566054DC5",
            isNativeToken: false
        ),
        rune,
        CoinMeta(
            chain: .thorChainChainnet,
            ticker: "RUNE",
            logo: "rune",
            decimals: 8,
            priceProviderId: "thorchain",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .thorChainStagenet,
            ticker: "RUNE",
            logo: "rune",
            decimals: 8,
            priceProviderId: "thorchain",
            contractAddress: "",
            isNativeToken: true
        ),
        tcy,
        stcy,
        ruji,
        sruji,
        CoinMeta(
            chain: .thorChain,
            ticker: "KUJI",
            logo: "kuji",
            decimals: 8,
            priceProviderId: "kujira",
            contractAddress: "thor.kuji",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .thorChain,
            ticker: "FUZN",
            logo: "fuzn",
            decimals: 8,
            priceProviderId: "fuzion",
            contractAddress: "thor.fuzn",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .thorChain,
            ticker: "NSTK",
            logo: "nstk",
            decimals: 8,
            priceProviderId: "unstake-fi",
            contractAddress: "thor.nstk",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .thorChain,
            ticker: "WINK",
            logo: "wink",
            decimals: 8,
            priceProviderId: "winkhub",
            contractAddress: "thor.wink",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .thorChain,
            ticker: "LVN",
            logo: "levana",
            decimals: 8,
            priceProviderId: "levana-protocol",
            contractAddress: "thor.lvn",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .thorChain,
            ticker: "RKUJI",
            logo: "rkuji",
            decimals: 8,
            priceProviderId: "kujira",
            contractAddress: "thor.rkuji",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .thorChain,
            ticker: "LQDY",
            logo: "lqdy",
            decimals: 8,
            // THORChain fiat is fetched from the pool endpoint, not CoinGecko, so
            // `priceProviderId` is a no-op here. LQDY has no L1 pool yet, so fiat
            // shows $0.00 until one launches; the balance still displays.
            priceProviderId: "",
            contractAddress: "thor.lqdy",
            isNativeToken: false
        ),
        yrune,
        ytcy,
        brune,
        ybrune,
        CoinMeta(
            chain: .ton,
            ticker: "GRAM",
            logo: "gram",
            decimals: 9,
            priceProviderId: "the-open-network",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .ton,
            ticker: "USDT",
            logo: "usdt",
            decimals: 6,
            priceProviderId: "tether",
            contractAddress: "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .tron,
            ticker: "TRX",
            logo: "tron",
            decimals: 6,
            priceProviderId: "tron",
            contractAddress: "",
            isNativeToken: true
        ),
        CoinMeta(
            chain: .tron,
            ticker: "USDT",
            logo: "usdt",
            decimals: 6,
            priceProviderId: "tether",
            contractAddress: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .tron,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "TEkxiTehnzSmSe2XqrBj4w32RUN966rdz8",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .tron,
            ticker: "USDD",
            logo: "usdd",
            decimals: 18,
            priceProviderId: "usdd",
            contractAddress: "TXDk8mbtRbXeYuMNS83CfKPaYYT8XWv9Hz",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .tron,
            ticker: "stUSDT",
            logo: "stusdt",
            decimals: 18,
            priceProviderId: "staked-usdt",
            contractAddress: "TThzxNRLrW2Brp9DcTQU8i4Wd9udCWEdZ3",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .zksync,
            ticker: "ETH",
            logo: "zsync_era",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "",
            isNativeToken: true
        ),
        avaxSol,
        baseCBBTC,
        baseVVV,
        bscBTCB,
        bscTWT,
        ethDPI,
        ethGUSD,
        ethLUSD,
        ethRAZE,
        ethTHOR,
        ethUSDP,
        ethVTHOR,
        ethXDEFI,
        ethXRUNE,
        ethWSTETH,
        ethLLD,
        ethMoca,
        arbLEO,
        arbYUM,
        arbGLD,
        arbWSTETH
    ]

    /// Look up a built-in token by chain and contract address (case-insensitive).
    static func findTokenMeta(chain: Chain, contractAddress: String) -> CoinMeta? {
        let addressLower = contractAddress.lowercased()
        return TokenSelectionAssets.first {
            $0.chain == chain && $0.contractAddress.lowercased() == addressLower
        }
    }

    static let rune: CoinMeta = CoinMeta(
        chain: .thorChain,
        ticker: "RUNE",
        logo: "rune",
        decimals: 8,
        priceProviderId: "thorchain",
        contractAddress: "",
        isNativeToken: true
    )

    static let luna: CoinMeta = CoinMeta(
        chain: .terra,
        ticker: "LUNA",
        logo: "luna",
        decimals: 6,
        priceProviderId: "terra-luna-2",
        contractAddress: "",
        isNativeToken: true
    )

    static let lunc: CoinMeta = CoinMeta(
        chain: .terraClassic,
        ticker: "LUNC",
        logo: "lunc",
        decimals: 6,
        priceProviderId: "terra-luna",
        contractAddress: "",
        isNativeToken: true
    )

    static let qbtc: CoinMeta = CoinMeta(
        chain: .qbtc,
        ticker: "QBTC",
        logo: "qbtc",
        decimals: 8,
        priceProviderId: "",
        contractAddress: "",
        isNativeToken: true
    )

    static let tcy: CoinMeta = CoinMeta(
        chain: .thorChain,
        ticker: "TCY",
        logo: "tcy",
        decimals: 8,
        priceProviderId: "tcy",
        contractAddress: "tcy",
        isNativeToken: false
    )

    /// Native TON coin (on-chain symbol "GRAM"). Used as the staking-position
    /// asset for the DeFi tab's TON nominator-pool flow.
    static let ton: CoinMeta = CoinMeta(
        chain: .ton,
        ticker: "GRAM",
        logo: "gram",
        decimals: 9,
        priceProviderId: "the-open-network",
        contractAddress: "",
        isNativeToken: true
    )

    static let ruji: CoinMeta = CoinMeta(
        chain: .thorChain,
        ticker: "RUJI",
        logo: "xruji",
        decimals: 8,
        priceProviderId: "rujira",
        contractAddress: "x/ruji",
        isNativeToken: false
    )

    static let sruji: CoinMeta = CoinMeta(
        chain: .thorChain,
        ticker: "sRUJI",
        logo: "xruji", // Use same logo as RUJI
        decimals: 8,
        priceProviderId: "rujira",
        // The on-chain denom for sRUJI is `x/staking-x/ruji` — PR #3837 renamed
        // this locally to `x/staking-ruji` (mirroring the sTCY rename) but the
        // chain never actually moved sRUJI, so the renamed contract didn't
        // match any balance. Restored to the real denom (see issue #4318).
        contractAddress: "x/staking-x/ruji",
        isNativeToken: false
    )

    static let stcy: CoinMeta = CoinMeta(
        chain: .thorChain,
        ticker: "sTCY",
        logo: "sTCY", // Use same logo as TCY
        decimals: 8,
        priceProviderId: "tcy",
        contractAddress: "x/staking-tcy",
        isNativeToken: false
    )

    static let yrune: CoinMeta = CoinMeta(
        chain: .thorChain,
        ticker: "yRUNE",
        logo: "yRUNE",
        decimals: 8,
        priceProviderId: "",
        contractAddress: "x/nami-index-nav-thor1mlphkryw5g54yfkrp6xpqzlpv4f8wh6hyw27yyg4z2els8a9gxpqhfhekt-rcpt",
        isNativeToken: false
    )

    static let ytcy: CoinMeta = CoinMeta(
        chain: .thorChain,
        ticker: "yTCY",
        logo: "yTCY",
        decimals: 8,
        priceProviderId: "",
        contractAddress: "x/nami-index-nav-thor1h0hr0rm3dawkedh44hlrmgvya6plsryehcr46yda2vj0wfwgq5xqrs86px-rcpt",
        isNativeToken: false
    )

    /// Rujira Bonded RUNE. Trades at ~RUNE parity, so it shares RUNE's price
    /// feed (`priceProviderId: "thorchain"` → the same CoinGecko id as RUNE).
    static let brune: CoinMeta = CoinMeta(
        chain: .thorChain,
        ticker: "bRUNE",
        logo: "brune",
        decimals: 8,
        priceProviderId: "thorchain",
        contractAddress: "x/brune",
        isNativeToken: false
    )

    /// Auto-compounding staking receipt for bRUNE (`x/staking-x/brune`).
    /// DeFi-only (excluded from the plain wallet list via `defiOnlyTickers`).
    /// Price is NAV-keyed on the contract denom (empty `priceProviderId`, like
    /// yRUNE/yTCY): `fetchYieldTokenPrice` resolves NAV × bRUNE.
    /// Shares the single `brune` icon (no distinct ybRUNE asset upstream,
    /// matching vultisig-android; mirrors sRUJI reusing xruji's logo).
    static let ybrune: CoinMeta = CoinMeta(
        chain: .thorChain,
        ticker: "ybRUNE",
        logo: "brune",
        decimals: 8,
        priceProviderId: "",
        contractAddress: "x/staking-x/brune",
        isNativeToken: false
    )

    // MARK: - THORChain LPs Tokens

    static let avaxSol: CoinMeta = CoinMeta(
        chain: .avalanche,
        ticker: "SOL",
        logo: "solana",
        decimals: 9,
        priceProviderId: "solana",
        contractAddress: "0xFE6B19286885a4F7F55AdAD09C3Cd1f906D2478F",
        isNativeToken: false
    )

    static let baseCBBTC: CoinMeta = CoinMeta(
        chain: .base,
        ticker: "cbBTC",
        logo: "btc",
        decimals: 8,
        priceProviderId: "coinbase-wrapped-btc",
        contractAddress: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf",
        isNativeToken: false
    )

    static let baseVVV: CoinMeta = CoinMeta(
        chain: .base,
        ticker: "VVV",
        logo: "vvv",
        decimals: 18,
        priceProviderId: "venice-token",
        contractAddress: "0xacfE6019Ed1A7Dc6f7B508C02d1b04ec88cC21bf",
        isNativeToken: false
    )

    static let bscBTCB: CoinMeta = CoinMeta(
        chain: .bscChain,
        ticker: "BTCB",
        logo: "btc",
        decimals: 18,
        priceProviderId: "bitcoin-on-base",
        contractAddress: "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c",
        isNativeToken: false
    )

    static let bscTWT: CoinMeta = CoinMeta(
        chain: .bscChain,
        ticker: "TWT",
        logo: "twt",
        decimals: 18,
        priceProviderId: "trust-wallet-token",
        contractAddress: "0x4B0F1812e5Df2A09796481Ff14017e6005508003",
        isNativeToken: false
    )

    static let ethDPI: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "DPI",
        logo: "dpi",
        decimals: 18,
        priceProviderId: "defipulse-index",
        contractAddress: "0x1494CA1F11D487c2bBe4543E90080AeBa4BA3C2b",
        isNativeToken: false
    )

    static let ethGUSD: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "GUSD",
        logo: "gusd",
        decimals: 2,
        priceProviderId: "gusd",
        contractAddress: "0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd",
        isNativeToken: false
    )

    static let ethLUSD: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "LUSD",
        logo: "lusd",
        decimals: 18,
        priceProviderId: "liquity-usd",
        contractAddress: "0x5f98805A4E8be255a32880FDeC7F6728C6568bA0",
        isNativeToken: false
    )

    static let ethRAZE: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "RAZE",
        logo: "raze",
        decimals: 18,
        priceProviderId: "",
        contractAddress: "0x5Eaa69B29f99C84Fe5dE8200340b4e9b4Ab38EaC",
        isNativeToken: false
    )

    static let ethTHOR: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "THOR",
        logo: "rune",
        decimals: 18,
        priceProviderId: "thor",
        contractAddress: "0xa5f2211B9b8170F694421f2046281775E8468044",
        isNativeToken: false
    )

    static let ethUSDP: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "USDP",
        logo: "usdp",
        decimals: 18,
        priceProviderId: "paxos-standard",
        contractAddress: "0x8E870D67F660D95d5be530380D0eC0bd388289E1",
        isNativeToken: false
    )

    static let ethVTHOR: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "vTHOR",
        logo: "vthor",
        decimals: 18,
        priceProviderId: "",
        contractAddress: "0x815C23eCA83261b6Ec689b60Cc4a58b54BC24D8D",
        isNativeToken: false
    )

    static let ethXDEFI: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "XDEFI",
        logo: "xdefi",
        decimals: 18,
        priceProviderId: "xdefi",
        contractAddress: "0x72B886d09C117654aB7dA13A14d603001dE0B777",
        isNativeToken: false
    )

    static let ethXRUNE: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "XRUNE",
        logo: "xrune",
        decimals: 18,
        priceProviderId: "thorstarter",
        contractAddress: "0x69fa0feE221AD11012BAb0FdB45d444D3D2Ce71c",
        isNativeToken: false
    )

    static let cacao: CoinMeta = CoinMeta(
        chain: .mayaChain,
        ticker: "CACAO",
        logo: "cacao",
        decimals: 10,
        priceProviderId: "cacao",
        contractAddress: "",
        isNativeToken: true
    )

    // MARK: - Maya Chain LPs Tokens

    static let ethWSTETH: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "WSTETH",
        logo: "wsteth",
        decimals: 18,
        priceProviderId: "wrapped-steth",
        contractAddress: "0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0",
        isNativeToken: false
    )

    static let ethLLD: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "LLD",
        logo: "lld",
        decimals: 18,
        priceProviderId: "liberland-lld",
        contractAddress: "0x054c9d4c6f4ea4e14391addd1812106c97d05690",
        isNativeToken: false
    )

    static let ethMoca: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "MOCA",
        logo: "moca",
        decimals: 18,
        priceProviderId: "",
        contractAddress: "0x53312F85Bba24C8cb99CFFc13BF82420157230d3",
        isNativeToken: false
    )

    static let arbLEO: CoinMeta = CoinMeta(
        chain: .arbitrum,
        ticker: "LEO",
        logo: "leo",
        decimals: 3,
        priceProviderId: "",
        contractAddress: "0x93864d81175095dd93360ffa2a529b8642F76A6E",
        isNativeToken: false
    )

    static let arbYUM: CoinMeta = CoinMeta(
        chain: .arbitrum,
        ticker: "YUM",
        logo: "yum",
        decimals: 18,
        priceProviderId: "",
        contractAddress: "0x9F41b34f42058a7b74672055a5fae22c4b113Fd1",
        isNativeToken: false
    )

    static let arbGLD: CoinMeta = CoinMeta(
        chain: .arbitrum,
        ticker: "GLD",
        logo: "gld",
        decimals: 18,
        priceProviderId: "",
        contractAddress: "0xaFD091f140C21770f4e5d53d26B2859Ae97555Aa",
        isNativeToken: false
    )

    static let arbWSTETH: CoinMeta = CoinMeta(
        chain: .arbitrum,
        ticker: "WSTETH",
        logo: "wsteth",
        decimals: 18,
        priceProviderId: "wrapped-steth",
        contractAddress: "0x5979D7b546E38E414F7E9822514be443A4800529",
        isNativeToken: false
    )

    static let ethUSDC: CoinMeta = CoinMeta(
        chain: .ethereum,
        ticker: "USDC",
        logo: "usdc",
        decimals: 6,
        priceProviderId: "usd-coin",
        contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        isNativeToken: false
    )
}
