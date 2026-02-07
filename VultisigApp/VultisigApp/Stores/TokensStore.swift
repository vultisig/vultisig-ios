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
        CoinMeta(
            chain: .ethereum,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            isNativeToken: false
        ),
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
            priceProviderId: "maya",
            contractAddress: "maya",
            isNativeToken: false
        ),
        CoinMeta(
            chain: .mayaChain,
            ticker: "AZTEC",
            logo: "aztec",
            decimals: 4,
            priceProviderId: "aztec",
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
        rune,
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
        yrune,
        ytcy,
        CoinMeta(
            chain: .ton,
            ticker: "TON",
            logo: "ton",
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

    static let rune: CoinMeta = CoinMeta(
        chain: .thorChain,
        ticker: "RUNE",
        logo: "rune",
        decimals: 8,
        priceProviderId: "thorchain",
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
        contractAddress: "x/staking-x/ruji",
        isNativeToken: false
    )

    static let stcy: CoinMeta = CoinMeta(
        chain: .thorChain,
        ticker: "sTCY",
        logo: "sTCY", // Use same logo as TCY
        decimals: 8,
        priceProviderId: "tcy",
        contractAddress: "x/staking-x/tcy",
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
}
