import Foundation
import WalletCore

class TokensStore {
    
    struct Token {
        // UTXO
        static var bitcoin: CoinMeta {
            CoinMeta(chain: Chain.bitcoin, ticker: "BTC", logo: "btc", decimals: 8, priceProviderId: "bitcoin", contractAddress: "", isNativeToken: true)
        }
        
        static var bitcoinCash: CoinMeta {
            CoinMeta(chain: Chain.bitcoinCash, ticker: "BCH", logo: "bch", decimals: 8, priceProviderId: "bitcoin-cash", contractAddress: "", isNativeToken: true)
        }
        
        static var litecoin: CoinMeta {
            CoinMeta(chain: Chain.litecoin, ticker: "LTC", logo: "ltc", decimals: 8, priceProviderId: "litecoin", contractAddress: "", isNativeToken: true)
        }
        
        static var dogecoin: CoinMeta {
            CoinMeta(chain: Chain.dogecoin, ticker: "DOGE", logo: "doge", decimals: 8, priceProviderId: "dogecoin", contractAddress: "", isNativeToken: true)
        }
        
        static var dash: CoinMeta {
            CoinMeta(chain: Chain.dash, ticker: "DASH", logo: "dash", decimals: 8, priceProviderId: "dash", contractAddress: "", isNativeToken: true)
        }
        
        static var thorChain: CoinMeta {
            CoinMeta(chain: Chain.thorChain, ticker: "RUNE", logo: "rune", decimals: 8, priceProviderId: "thorchain", contractAddress: "", isNativeToken: true)
        }
        
        static var mayaChainCacao: CoinMeta {
            CoinMeta(chain: Chain.mayaChain, ticker: "CACAO", logo: "cacao", decimals: 10, priceProviderId: "cacao", contractAddress: "", isNativeToken: true)
        }
        
        static var mayaChainMaya: CoinMeta {
            CoinMeta(chain: Chain.mayaChain, ticker: "MAYA", logo: "maya", decimals: 4, priceProviderId: "maya", contractAddress: "", isNativeToken: false)
        }
        
        static var solana: CoinMeta {
            CoinMeta(chain: Chain.solana, ticker: "SOL", logo: "solana", decimals: 9, priceProviderId: "solana", contractAddress: "", isNativeToken: true)
        }
        
        static var solanaJupiter: CoinMeta {
            CoinMeta(chain: Chain.solana, ticker: "JUP", logo: "jupiter", decimals: 6, priceProviderId: "jupiter-exchange-solana", contractAddress: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN", isNativeToken: false)
        }
        
        static var solanaWif: CoinMeta {
            CoinMeta(chain: Chain.solana, ticker: "WIF", logo: "dogwifhat-wif-logo", decimals: 6, priceProviderId: "dogwifcoin", contractAddress: "EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm", isNativeToken: false)
        }
        
        static var solanaPyth: CoinMeta {
            CoinMeta(chain: Chain.solana, ticker: "PYTH", logo: "pyth-network-pyth-logo", decimals: 6, priceProviderId: "pyth-network", contractAddress: "HZ1JovNiVvGrGNiiYvEozEVgZ58xaU3RKwX8eACQBCt3", isNativeToken: false)
        }
        
        static var solanaUsdc: CoinMeta {
            CoinMeta(chain: Chain.solana, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "usd-coin", contractAddress: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", isNativeToken: false)
        }
        
        static var solanaUsdt: CoinMeta {
            CoinMeta(chain: Chain.solana, ticker: "USDT", logo: "usdt", decimals: 6, priceProviderId: "tether", contractAddress: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", isNativeToken: false)
        }
        
        static var solanaRaydium: CoinMeta {
            CoinMeta(chain: Chain.solana, ticker: "RAY", logo: "raydium-ray-seeklogo-2", decimals: 6, priceProviderId: "raydium", contractAddress: "4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R", isNativeToken: false)
        }
        
        // EVMS
        
        // ETH
        // https://etherscan.io/tokens
        
        static var ethereum: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "ETH", logo: "eth", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true)
        }
        
        static var ethereumUsdc: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "usd-coin", contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", isNativeToken: false)
        }
        
        static var ethereumUsdt: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "USDT", logo: "usdt", decimals: 6, priceProviderId: "tether", contractAddress: "0xdac17f958d2ee523a2206206994597c13d831ec7", isNativeToken: false)
        }
        
        static var ethereumUni: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "UNI", logo: "uni", decimals: 18, priceProviderId: "uniswap", contractAddress: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984", isNativeToken: false)
        }
        
        static var ethereumPol: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "POL", logo: "pol", decimals: 18, priceProviderId: "matic-network", contractAddress: "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0", isNativeToken: false)
        }
        
        static var ethereumWbtc: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "WBTC", logo: "wbtc", decimals: 8, priceProviderId: "wrapped-bitcoin", contractAddress: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", isNativeToken: false)
        }
        
        static var ethereumLink: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "LINK", logo: "link", decimals: 18, priceProviderId: "chainlink", contractAddress: "0x514910771af9ca656af840dff83e8264ecf986ca", isNativeToken: false)
        }
        
        static var ethereumFlip: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "FLIP", logo: "flip", decimals: 18, priceProviderId: "chainflip", contractAddress: "0x826180541412d574cf1336d22c0c0a287822678a", isNativeToken: false)
        }
        
        static var ethereumTgt: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "TGT", logo: "tgt", decimals: 18, priceProviderId: "thorwallet", contractAddress: "0x108a850856Db3f85d0269a2693D896B394C80325", isNativeToken: false)
        }
        
        static var ethereumFox: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "FOX", logo: "fox", decimals: 18, priceProviderId: "shapeshift-fox-token", contractAddress: "0xc770eefad204b5180df6a14ee197d99d808ee52d", isNativeToken: false)
        }
        
        static var ethereumDai: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "DAI", logo: "dai", decimals: 18, priceProviderId: "dai", contractAddress: "0x6b175474e89094c44da98b954eedeac495271d0f", isNativeToken: false)
        }
        static var ethereumWeth: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "WETH", logo: "weth", decimals: 18, priceProviderId: "weth", contractAddress: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", isNativeToken: false)
        }
        static var ethereumYfi: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "YFI", logo: "yfi", decimals: 18, priceProviderId: "yearn-finance", contractAddress: "0x0bc529c00c6401aef6d220be8c6ea1667f6ad93e", isNativeToken: false)
        }
        static var ethereumAave: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "AAVE", logo: "aave", decimals: 18, priceProviderId: "aave", contractAddress: "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9", isNativeToken: false)
        }
        // I DIDN'T find LEND
        static var ethereumComp: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "COMP", logo: "comp", decimals: 18, priceProviderId: "compound-governance-token", contractAddress: "0xc00e94cb662c3520282e6f5717214004a7f26888", isNativeToken: false)
        }
        static var ethereumBat: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "BAT", logo: "bat", decimals: 18, priceProviderId: "basic-attention-token", contractAddress: "0x0d8775f648430679a709e98d2b0cb6250d2887ef", isNativeToken: false)
        }
        static var ethereumSnx: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "SNX", logo: "snx", decimals: 18, priceProviderId: "havven", contractAddress: "0xc011a73ee8576fb46f5e1c5751ca3b9fe0af2a6f", isNativeToken: false)
        }
        static var ethereumBal: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "BAL", logo: "bal", decimals: 18, priceProviderId: "balancer", contractAddress: "0xba100000625a3754423978a60c9317c58a424e3d", isNativeToken: false)
        }
        static var ethereumSushi: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "SUSHI", logo: "sushi", decimals: 18, priceProviderId: "sushi", contractAddress: "0x6b3595068778dd592e39a122f4f5a5cf09c90fe2", isNativeToken: false)
        }
        static var ethereumMkr: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "MKR", logo: "mkr", decimals: 18, priceProviderId: "maker", contractAddress: "0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2", isNativeToken: false)
        }
        static var ethereumKnc: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "KNC", logo: "knc", decimals: 18, priceProviderId: "kyber-network-crystal", contractAddress: "0xdefa4e8a7bcba345f687a2f1456f5edd9ce97202", isNativeToken: false)
        }
        static var ethereumGrt: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "GRT", logo: "grt", decimals: 18, priceProviderId: "the-graph", contractAddress: "0xc944e90c64b2c07662a292be6244bdf05cda44a7", isNativeToken: false)
        }
        static var ethereumPepe: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "PEPE", logo: "pepe", decimals: 18, priceProviderId: "pepe", contractAddress: "0x6982508145454ce325ddbe47a25d4ec3d2311933", isNativeToken: false)
        }
        
        // AVALANCHE
        // https://avascan.info/blockchain/all/marketcap
        
        static var avalanche: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "AVAX", logo: "avax", decimals: 18, priceProviderId: "avalanche-2", contractAddress: "", isNativeToken: true)
        }
        
        static var avalancheUsdc: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "", contractAddress: "0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e", isNativeToken: false)
        }
        
        static var avalancheUsdt: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "USDT", logo: "usdt", decimals: 6, priceProviderId: "", contractAddress: "0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7", isNativeToken: false)
        }
        
        static var avalancheBtc: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "BTC.b", logo: "btc", decimals: 8, priceProviderId: "", contractAddress: "0x152b9d0FdC40C096757F570A51E494bd4b943E50", isNativeToken: false)
        }
        
        static var avalancheSAvax: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "sAVAX", logo: "savax", decimals: 18, priceProviderId: "", contractAddress: "0x2b2C81e08f1Af8835a78Bb2A90AE924ACE0eA4bE", isNativeToken: false)
        }
        
        static var avalancheJOE: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "JOE", logo: "joe", decimals: 18, priceProviderId: "", contractAddress: "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd", isNativeToken: false)
        }
        
        static var avalanchePNG: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "PNG", logo: "png", decimals: 18, priceProviderId: "", contractAddress: "0x60781C2586D68229fde47564546784ab3fACA982", isNativeToken: false)
        }
        
        static var avalancheWAVAX: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "WAVAX", logo: "avax", decimals: 18, priceProviderId: "", contractAddress: "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7", isNativeToken: false)
        }
        
        static var avalancheAAvaUSDC: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "aAvaUSDC", logo: "aave", decimals: 6, priceProviderId: "", contractAddress: "0x625E7708f30cA75bfd92586e17077590C60eb4cD", isNativeToken: false)
        }
        
        static var avalancheBLS: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "BLS", logo: "bls", decimals: 18, priceProviderId: "", contractAddress: "0x46B9144771Cb3195D66e4EDA643a7493fADCAF9D", isNativeToken: false)
        }
        
        static var avalancheCOQ: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "COQ", logo: "coq", decimals: 18, priceProviderId: "", contractAddress: "0x420FcA0121DC28039145009570975747295f2329", isNativeToken: false)
        }
        
        // BSC
        static var bscChainBnb: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "BNB", logo: "bsc", decimals: 18, priceProviderId: "binancecoin", contractAddress: "", isNativeToken: true)
        }
        
        static var bscChainUsdt: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "USDT", logo: "usdt", decimals: 18, priceProviderId: "", contractAddress: "0x55d398326f99059fF775485246999027B3197955", isNativeToken: false)
        }
        
        static var bscChainUsdc: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "USDC", logo: "usdc", decimals: 18, priceProviderId: "", contractAddress: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d", isNativeToken: false)
        }
        
        static var bscDai: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "DAI", logo: "dai", decimals: 18, priceProviderId: "", contractAddress: "0x1af3f329e8be154074d8769d1ffa4ee058b1dbc3", isNativeToken: false)
        }
        static var bscWeth: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "WETH", logo: "weth", decimals: 18, priceProviderId: "", contractAddress: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", isNativeToken: false)
        }
        static var bscAave: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "AAVE", logo: "aave", decimals: 18, priceProviderId: "", contractAddress: "0xfb6115445bff7b52feb98650c87f44907e58f802", isNativeToken: false)
        }
        static var bscComp: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "COMP", logo: "comp", decimals: 18, priceProviderId: "", contractAddress: "0x52ce071bd9b1c4b00a0b92d298c512478cad67e8", isNativeToken: false)
        }
        static var bscSushi: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "SUSHI", logo: "sushi", decimals: 18, priceProviderId: "", contractAddress: "0x947950bcc74888a40ffa2593c5798f11fc9124c4", isNativeToken: false)
        }
        static var bscKnc: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "KNC", logo: "knc", decimals: 18, priceProviderId: "", contractAddress: "0xfe56d5892bdffc7bf58f2e84be1b2c32d21c308b", isNativeToken: false)
        }
        static var bscPepe: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "PEPE", logo: "pepe", decimals: 18, priceProviderId: "", contractAddress: "0x25d887ce7a35172c62febfd67a1856f20faebb00", isNativeToken: false)
        }
        
        //
        
        // BASE
        
        static var baseEth: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "ETH", logo: "eth", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true)
        }
        
        static var baseUsdc: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "usd-coin", contractAddress: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", isNativeToken: false)
        }
        
        static var baseWewe: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "WEWE", logo: "wewe", decimals: 18, priceProviderId: "", contractAddress: "0x6b9bb36519538e0C073894E964E90172E1c0B41F", isNativeToken: false)
        }
        
        static var baseDai: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "DAI", logo: "dai", decimals: 18, priceProviderId: "dai", contractAddress: "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb", isNativeToken: false)
        }
        
        static var baseRETH: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "rETH", logo: "reth", decimals: 18, priceProviderId: "reth", contractAddress: "0xB6fe221Fe9EeF5aBa221c348bA20A1Bf5e73624c", isNativeToken: false)
        }
        
        static var baseEZETH: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "ezETH", logo: "ezeth", decimals: 18, priceProviderId: "ezeth", contractAddress: "0x2416092f143378750bb29b79eD961ab195CcEea5", isNativeToken: false)
        }
        
        static var basePYTH: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "PYTH", logo: "pyth", decimals: 18, priceProviderId: "pyth", contractAddress: "0x4c5d8A75F3762c1561D96f177694f67378705E98", isNativeToken: false)
        }
        
        static var baseOM: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "OM", logo: "om", decimals: 18, priceProviderId: "om", contractAddress: "0x3992B27dA26848C2b19CeA6Fd25ad5568B68AB98", isNativeToken: false)
        }
        
        static var baseW: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "W", logo: "w", decimals: 18, priceProviderId: "w", contractAddress: "0xB0fFa8000886e57F86dd5264b9582b2Ad87b2b91", isNativeToken: false)
        }
        
        static var baseCBETH: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "cbETH", logo: "cbeth", decimals: 18, priceProviderId: "cbETH", contractAddress: "0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22", isNativeToken: false)
        }
        
        static var baseSNX: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "SNX", logo: "snx", decimals: 18, priceProviderId: "SNX", contractAddress: "0x22e6966B799c4D5B13BE962E1D117b56327FDa66", isNativeToken: false)
        }
        
        static var baseAERO: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "AERO", logo: "aero", decimals: 18, priceProviderId: "AERO", contractAddress: "0x940181a94A35A4569E4529A3CDfB74e38FD98631", isNativeToken: false)
        }
        
        //
        
        static var arbETH: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "ETH", logo: "eth", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true)
        }
        
        static var arbArb: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "ARB", logo: "arbitrum", decimals: 18, priceProviderId: "arbitrum", contractAddress: "0x912ce59144191c1204e64559fe8253a0e49e6548", isNativeToken: false)
        }
        
        static var arbTGT: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "TGT", logo: "tgt", decimals: 18, priceProviderId: "thorwallet", contractAddress: "0x429fEd88f10285E61b12BDF00848315fbDfCC341", isNativeToken: false)
        }
        
        static var arbFox: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "FOX", logo: "fox", decimals: 18, priceProviderId: "shapeshift-fox-token", contractAddress: "0xf929de51D91C77E42f5090069E0AD7A09e513c73", isNativeToken: false)
        }
        
        static var arbUSDT: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "USDT", logo: "usdt", decimals: 6, priceProviderId: "USDT", contractAddress: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", isNativeToken: false)
        }
        
        static var arbUSDCe: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "USDC.e", logo: "usdc", decimals: 6, priceProviderId: "USDC.e", contractAddress: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8", isNativeToken: false)
        }
        
        static var arbUSDC: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "USDC", contractAddress: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", isNativeToken: false)
        }
        
        static var arbWBTC: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "WBTC", logo: "wbtc", decimals: 8, priceProviderId: "WBTC", contractAddress: "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f", isNativeToken: false)
        }
        
        static var arbLINK: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "LINK", logo: "link", decimals: 18, priceProviderId: "LINK", contractAddress: "0xf97f4df75117a78c1A5a0DBb814Af92458539FB4", isNativeToken: false)
        }
        
        static var arbDAI: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "DAI", logo: "dai", decimals: 18, priceProviderId: "DAI", contractAddress: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1", isNativeToken: false)
        }
        
        static var arbUNI: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "UNI", logo: "uni", decimals: 18, priceProviderId: "UNI", contractAddress: "0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0", isNativeToken: false)
        }
        
        static var arbPEPE: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "PEPE", logo: "pepe", decimals: 18, priceProviderId: "PEPE", contractAddress: "0x25d887Ce7a35172C62FeBFD67a1856F20FaEbB00", isNativeToken: false)
        }
        
        static var arbGRT: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "GRT", logo: "grt", decimals: 18, priceProviderId: "GRT", contractAddress: "0x9623063377AD1B27544C965cCd7342f7EA7e88C7", isNativeToken: false)
        }
        
        static var arbEZETH: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "ezETH", logo: "ezeth", decimals: 18, priceProviderId: "ezETH", contractAddress: "0x2416092f143378750bb29b79eD961ab195CcEea5", isNativeToken: false)
        }
        
        static var arbPYTH: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "PYTH", logo: "pyth", decimals: 6, priceProviderId: "PYTH", contractAddress: "0xE4D5c6aE46ADFAF04313081e8C0052A30b6Dd724", isNativeToken: false)
        }
        
        static var arbLDO: CoinMeta {
            CoinMeta(chain: Chain.arbitrum, ticker: "LDO", logo: "ldo", decimals: 18, priceProviderId: "LDO", contractAddress: "0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60", isNativeToken: false)
        }
        
        // OPTIMUM
        
        static var optETH: CoinMeta {
            CoinMeta(chain: Chain.optimism, ticker: "ETH", logo: "eth", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true)
        }
        
        static var optOP: CoinMeta {
            CoinMeta(chain: Chain.optimism, ticker: "OP", logo: "optimism", decimals: 18, priceProviderId: "", contractAddress: "0x4200000000000000000000000000000000000042", isNativeToken: false)
        }
        
        static var optFox: CoinMeta {
            CoinMeta(chain: Chain.optimism, ticker: "FOX", logo: "fox", decimals: 18, priceProviderId: "", contractAddress: "0xf1a0da3367bc7aa04f8d94ba57b862ff37ced174", isNativeToken: false)
        }
        
        static var optUSDT: CoinMeta {
            CoinMeta(chain: Chain.optimism, ticker: "USDT", logo: "usdt", decimals: 6, priceProviderId: "", contractAddress: "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58", isNativeToken: false)
        }
        
        static var optUSDC: CoinMeta {
            CoinMeta(chain: Chain.optimism, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "", contractAddress: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85", isNativeToken: false)
        }
        
        static var optUSDCe: CoinMeta {
            CoinMeta(chain: Chain.optimism, ticker: "USDC.e", logo: "usdc", decimals: 6, priceProviderId: "", contractAddress: "0x7F5c764cBc14f9669B88837ca1490cCa17c31607", isNativeToken: false)
        }
        
        static var optWBTC: CoinMeta {
            CoinMeta(chain: Chain.optimism, ticker: "WBTC", logo: "wbtc", decimals: 8, priceProviderId: "", contractAddress: "0x68f180fcCe6836688e9084f035309E29Bf0A2095", isNativeToken: false)
        }
        
        static var optLINK: CoinMeta {
            CoinMeta(chain: Chain.optimism, ticker: "LINK", logo: "link", decimals: 18, priceProviderId: "", contractAddress: "0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6", isNativeToken: false)
        }
        
        static var optDAI: CoinMeta {
            CoinMeta(chain: Chain.optimism, ticker: "DAI", logo: "dai", decimals: 18, priceProviderId: "", contractAddress: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1", isNativeToken: false)
        }
        
        static var optEZETH: CoinMeta {
            CoinMeta(chain: Chain.optimism, ticker: "ezETH", logo: "ezeth", decimals: 18, priceProviderId: "", contractAddress: "0x2416092f143378750bb29b79eD961ab195CcEea5", isNativeToken: false)
        }
        
        static var optPYTH: CoinMeta {
            CoinMeta(chain: Chain.optimism, ticker: "PYTH", logo: "pyth", decimals: 6, priceProviderId: "", contractAddress: "0x99C59ACeBFEF3BBFB7129DC90D1a11DB0E91187f", isNativeToken: false)
        }
        
        static var optLDO: CoinMeta {
            CoinMeta(chain: Chain.optimism, ticker: "LDO", logo: "ldo", decimals: 18, priceProviderId: "", contractAddress: "0xFdb794692724153d1488CcdBE0C56c252596735F", isNativeToken: false)
        }
        
        // POLYGON

        static var pol: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "POL", logo: "pol", decimals: 18, priceProviderId: "matic-network", contractAddress: "", isNativeToken: true)
        }
        
        static var polWETH: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "WETH", logo: "weth", decimals: 18, priceProviderId: "", contractAddress: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", isNativeToken: false)
        }
        
        static var polFox: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "FOX", logo: "fox", decimals: 18, priceProviderId: "", contractAddress: "0x65a05db8322701724c197af82c9cae41195b0aa8", isNativeToken: false)
        }
        
        static var polUSDT: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "USDT", logo: "usdt", decimals: 6, priceProviderId: "", contractAddress: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F", isNativeToken: false)
        }
        
        static var polBNB: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "BNB", logo: "bsc", decimals: 18, priceProviderId: "", contractAddress: "0x3BA4c387f786bFEE076A58914F5Bd38d668B42c3", isNativeToken: false)
        }
        
        static var polSOL: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "SOL", logo: "solana", decimals: 9, priceProviderId: "", contractAddress: "0xd93f7E271cB87c23AaA73edC008A79646d1F9912", isNativeToken: false)
        }
        
        static var polUSDC: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "", contractAddress: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359", isNativeToken: false)
        }
        
        static var polUSDCe: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "USDC.e", logo: "usdc", decimals: 6, priceProviderId: "", contractAddress: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", isNativeToken: false)
        }
        
        static var polBUSD: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "BUSD", logo: "busd", decimals: 18, priceProviderId: "", contractAddress: "0xdAb529f40E671A1D4bF91361c21bf9f0C9712ab7", isNativeToken: false)
        }
        
        static var polWBTC: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "WBTC", logo: "wbtc", decimals: 8, priceProviderId: "", contractAddress: "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6", isNativeToken: false)
        }
        
        static var polAVAX: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "AVAX", logo: "avax", decimals: 18, priceProviderId: "", contractAddress: "0x2C89bbc92BD86F8075d1DEcc58C7F4E0107f286b", isNativeToken: false)
        }
        
        static var polSHIB: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "SHIB", logo: "shib", decimals: 18, priceProviderId: "", contractAddress: "0x6f8a06447Ff6FcF75d803135a7de15CE88C1d4ec", isNativeToken: false)
        }
        
        static var polLINK: CoinMeta {
            CoinMeta(chain: Chain.polygon, ticker: "LINK", logo: "link", decimals: 18, priceProviderId: "", contractAddress: "0xb0897686c545045aFc77CF20eC7A532E3120E0F1", isNativeToken: false)
        }
        
        // BLAST
        
        static var blastETH: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "ETH", logo: "eth", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true)
        }
        
        static var blastWETH: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "WETH", logo: "weth", decimals: 18, priceProviderId: "ethereum", contractAddress: "0x4300000000000000000000000000000000000004", isNativeToken: false)
        }
        
        static var blastWBTC: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "WBTC", logo: "wbtc", decimals: 8, priceProviderId: "", contractAddress: "0xF7bc58b8D8f97ADC129cfC4c9f45Ce3C0E1D2692", isNativeToken: false)
        }
        
        static var blastUSDB: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "USDB", logo: "usdb", decimals: 18, priceProviderId: "", contractAddress: "0x4300000000000000000000000000000000000003", isNativeToken: false)
        }
        
        static var blastBLAST: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "BLAST", logo: "blast", decimals: 18, priceProviderId: "", contractAddress: "0xb1a5700fA2358173Fe465e6eA4Ff52E36e88E2ad", isNativeToken: false)
        }
        
        static var blastMIM: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "MIM", logo: "mim", decimals: 18, priceProviderId: "", contractAddress: "0x76DA31D7C9CbEAE102aff34D3398bC450c8374c1", isNativeToken: false)
        }
        
        static var blastBLOOKS: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "bLOOKS", logo: "blooks", decimals: 18, priceProviderId: "", contractAddress: "0x406F10d635be12ad33D6B133C6DA89180f5B999e", isNativeToken: false)
        }
        
        static var blastBAG: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "BAG", logo: "bag", decimals: 18, priceProviderId: "", contractAddress: "0xb9dfCd4CF589bB8090569cb52FaC1b88Dbe4981F", isNativeToken: false)
        }
        
        static var blastZERO: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "ZERO", logo: "zero", decimals: 18, priceProviderId: "", contractAddress: "0x357f93E17FdabEcd3fEFc488a2d27dff8065d00f", isNativeToken: false)
        }
        
        static var blastAI: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "AI", logo: "anyinu", decimals: 18, priceProviderId: "", contractAddress: "0x764933fbAd8f5D04Ccd088602096655c2ED9879F", isNativeToken: false)
        }
        
        static var blastJUICE: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "JUICE", logo: "juice", decimals: 18, priceProviderId: "", contractAddress: "0x818a92bc81Aad0053d72ba753fb5Bc3d0C5C0923", isNativeToken: false)
        }
        
        static var blastOMNI: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "OMNI", logo: "omni", decimals: 18, priceProviderId: "", contractAddress: "0x9e20461bc2c4c980f62f1B279D71734207a6A356", isNativeToken: false)
        }
        
        static var blastDACKIE: CoinMeta {
            CoinMeta(chain: Chain.blast, ticker: "DACKIE", logo: "dackie", decimals: 18, priceProviderId: "", contractAddress: "0x47C337Bd5b9344a6F3D6f58C474D9D8cd419D8cA", isNativeToken: false)
        }
        
        //
        
        static var cronosCRO: CoinMeta {
            CoinMeta(chain: Chain.cronosChain, ticker: "CRO", logo: "cro", decimals: 18, priceProviderId: "crypto-com-chain", contractAddress: "", isNativeToken: true)
        }
        
        static var suiSUI: CoinMeta {
            CoinMeta(chain: Chain.sui, ticker: "SUI", logo: "sui", decimals: 9, priceProviderId: "sui", contractAddress: "", isNativeToken: true)
        }
        
        static var ton: CoinMeta {
            CoinMeta(chain: Chain.ton, ticker: "TON", logo: "ton", decimals: 9, priceProviderId: "the-open-network", contractAddress: "", isNativeToken: true)
        }
        
        static var dotDOT: CoinMeta {
            CoinMeta(chain: Chain.polkadot, ticker: "DOT", logo: "dot", decimals: 10, priceProviderId: "polkadot", contractAddress: "", isNativeToken: true)
        }
        
        static var gaiaChainAtom: CoinMeta {
            CoinMeta(chain: Chain.gaiaChain, ticker: "ATOM", logo: "atom", decimals: 6, priceProviderId: "cosmos", contractAddress: "", isNativeToken: true)
        }
                
        static var gaiaChainUsdc: CoinMeta {
            CoinMeta(chain: Chain.gaiaChain, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "usd-coin", contractAddress: "ibc/F663521BF1836B00F5F177680F74BFB9A8B5654A694D0D2BC249E03CF2509013", isNativeToken: false)
        }
        
        static var osmosis: CoinMeta {
            CoinMeta(chain: Chain.osmosis, ticker: "OSMO", logo: "osmo", decimals: 6, priceProviderId: "osmosis", contractAddress: "", isNativeToken: true)
        }
        
        static var osmosisUsdc: CoinMeta {
            CoinMeta(chain: Chain.osmosis, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "usd-coin", contractAddress: "ibc/498A0751C798A0D9A389AA3691123DADA57DAA4FE165D5C75894505B876BA6E4", isNativeToken: false)
        }
        
        static var osmosisIon: CoinMeta {
            CoinMeta(chain: Chain.osmosis, ticker: "ION", logo: "ion", decimals: 6, priceProviderId: "ion", contractAddress: "uion", isNativeToken: false)
        }
        
        static var terra: CoinMeta {
            CoinMeta(chain: Chain.terra, ticker: "LUNA", logo: "luna", decimals: 6, priceProviderId: "terra-luna-2", contractAddress: "", isNativeToken: true)
        }
        
        static var terraTPT: CoinMeta {
            CoinMeta(chain: Chain.terra, ticker: "TPT", logo: "terra-poker-token", decimals: 6, priceProviderId: "tpt", contractAddress: "terra13j2k5rfkg0qhk58vz63cze0uze4hwswlrfnm0fa4rnyggjyfrcnqcrs5z2", isNativeToken: false)
        }
        
        static var terraAstroIBC: CoinMeta {
            CoinMeta(chain: Chain.terra, ticker: "ASTRO-IBC", logo: "terra-astroport", decimals: 6, priceProviderId: "astroport-fi", contractAddress: "ibc/8D8A7F7253615E5F76CB6252A1E1BD921D5EDB7BBAAF8913FB1C77FF125D9995", isNativeToken: false)
        }
        
        static var terraAstro: CoinMeta {
            CoinMeta(chain: Chain.terra, ticker: "ASTRO", logo: "terra-astroport", decimals: 6, priceProviderId: "astroport-fi", contractAddress: "terra1nsuqsk6kh58ulczatwev87ttq2z6r3pusulg9r24mfj2fvtzd4uq3exn26", isNativeToken: false)
        }
        
        static var terraClassic: CoinMeta {
            CoinMeta(chain: Chain.terraClassic, ticker: "LUNC", logo: "lunc", decimals: 6, priceProviderId: "terra-luna", contractAddress: "", isNativeToken: true)
        }
        
        static var terraClassicUSD: CoinMeta {
            CoinMeta(chain: Chain.terraClassic, ticker: "USTC", logo: "ustc", decimals: 6, priceProviderId: "terrausd", contractAddress: "uusd", isNativeToken: false)
        }
                
        static var terraClassicAstro: CoinMeta {
            CoinMeta(chain: Chain.terraClassic, ticker: "ASTROC", logo: "terra-astroport", decimals: 6, priceProviderId: "astroport", contractAddress: "terra1xj49zyqrwpv5k928jwfpfy2ha668nwdgkwlrg3", isNativeToken: false)
        }
        
        static var kujira: CoinMeta {
            CoinMeta(chain: Chain.kujira, ticker: "KUJI", logo: "kuji", decimals: 6, priceProviderId: "kujira", contractAddress: "", isNativeToken: true)
        }
        
        static var kujiraAstro: CoinMeta {
            CoinMeta(chain: Chain.kujira, ticker: "ASTRO", logo: "terra-astroport", decimals: 6, priceProviderId: "astroport-fi", contractAddress: "ibc/640E1C3E28FD45F611971DF891AE3DC90C825DF759DF8FAA8F33F7F72B35AD56", isNativeToken: false)
        }
        
        static var kujiraLunc: CoinMeta {
            CoinMeta(chain: Chain.kujira, ticker: "LUNC", logo: "lunc", decimals: 6, priceProviderId: "terra-luna", contractAddress: "ibc/119334C55720942481F458C9C462F5C0CD1F1E7EEAC4679D674AA67221916AEA", isNativeToken: false)
        }
        
        static var kujiraUsdc: CoinMeta {
            CoinMeta(chain: Chain.kujira, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "usd-coin", contractAddress: "ibc/FE98AAD68F02F03565E9FA39A5E627946699B2B07115889ED812D8BA639576A9", isNativeToken: false)
        }
        
        static var kujiraMnta: CoinMeta {
            CoinMeta(chain: Chain.kujira, ticker: "MNTA", logo: "mnta", decimals: 6, priceProviderId: "mantadao", contractAddress: "factory/kujira1643jxg8wasy5cfcn7xm8rd742yeazcksqlg4d7/umnta", isNativeToken: false)
        }
        
        static var kujiraNSTK: CoinMeta {
            CoinMeta(chain: Chain.kujira, ticker: "NSTK", logo: "nstk", decimals: 6, priceProviderId: "unstake-fi", contractAddress: "factory/kujira1aaudpfr9y23lt9d45hrmskphpdfaq9ajxd3ukh/unstk", isNativeToken: false)
        }
        
        static var kujiraWINK: CoinMeta {
            CoinMeta(chain: Chain.kujira, ticker: "WINK", logo: "wink", decimals: 6, priceProviderId: "winkhub", contractAddress: "factory/kujira12cjjeytrqcj25uv349thltcygnp9k0kukpct0e/uwink", isNativeToken: false)
        }
        
        static var kujiraUSK: CoinMeta {
            CoinMeta(chain: Chain.kujira, ticker: "USK", logo: "usk", decimals: 6, priceProviderId: "usk", contractAddress: "factory/kujira1qk00h5atutpsv900x202pxx42npjr9thg58dnqpa72f2p7m2luase444a7/uusk", isNativeToken: false)
        }
        
        static var dydx: CoinMeta {
            CoinMeta(chain: Chain.dydx, ticker: "DYDX", logo: "dydx", decimals: 18, priceProviderId: "dydx-chain", contractAddress: "", isNativeToken: true)
        }
        
        static var nobleUsdc: CoinMeta {
            CoinMeta(chain: Chain.noble, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "usd-coin", contractAddress: "", isNativeToken: true)
        }
        
        static var zksyncETH: CoinMeta {
            CoinMeta(chain: Chain.zksync, ticker: "ETH", logo: "zsync_era", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true)
        }
    }
    
    static var TokenSelectionAssets = [
        TokensStore.Token.bitcoin,
        TokensStore.Token.bitcoinCash,
        TokensStore.Token.litecoin,
        TokensStore.Token.dogecoin,
        TokensStore.Token.dash,
        TokensStore.Token.thorChain,
        TokensStore.Token.mayaChainCacao,
        TokensStore.Token.mayaChainMaya,
        
        
        TokensStore.Token.solana,
        TokensStore.Token.solanaJupiter,
        TokensStore.Token.solanaWif,
        TokensStore.Token.solanaPyth,
        TokensStore.Token.solanaUsdc,
        TokensStore.Token.solanaUsdt,
        TokensStore.Token.solanaRaydium,
        
        TokensStore.Token.osmosis,
        TokensStore.Token.osmosisUsdc,
        TokensStore.Token.osmosisIon,
        
        TokensStore.Token.gaiaChainAtom,
        TokensStore.Token.gaiaChainUsdc,
        
        TokensStore.Token.kujira,
        TokensStore.Token.kujiraAstro,
        TokensStore.Token.kujiraLunc,
        TokensStore.Token.kujiraUsdc,
        TokensStore.Token.kujiraMnta,
        
        TokensStore.Token.kujiraUSK,
        TokensStore.Token.kujiraNSTK,
        TokensStore.Token.kujiraWINK,

        
        
        TokensStore.Token.dydx,
        
        TokensStore.Token.nobleUsdc,
        
        TokensStore.Token.terra,
        TokensStore.Token.terraAstro,
        TokensStore.Token.terraAstroIBC,
        TokensStore.Token.terraTPT,
        
        
        TokensStore.Token.terraClassic,
        TokensStore.Token.terraClassicAstro,
        TokensStore.Token.terraClassicUSD,

        TokensStore.Token.suiSUI,
        TokensStore.Token.dotDOT,
        TokensStore.Token.ton,
        
        // START EVMS
        // ETHEREUM
        TokensStore.Token.ethereum,
        TokensStore.Token.ethereumUsdc,
        TokensStore.Token.ethereumUsdt,
        TokensStore.Token.ethereumUni,
        TokensStore.Token.ethereumPol,
        TokensStore.Token.ethereumWbtc,
        TokensStore.Token.ethereumLink,
        TokensStore.Token.ethereumFlip,
        TokensStore.Token.ethereumTgt,
        TokensStore.Token.ethereumFox,
        TokensStore.Token.ethereumDai,
        TokensStore.Token.ethereumWeth,
        TokensStore.Token.ethereumYfi,
        TokensStore.Token.ethereumAave,
        TokensStore.Token.ethereumComp,
        TokensStore.Token.ethereumBat,
        TokensStore.Token.ethereumSnx,
        TokensStore.Token.ethereumBal,
        TokensStore.Token.ethereumSushi,
        TokensStore.Token.ethereumMkr,
        TokensStore.Token.ethereumKnc,
        TokensStore.Token.ethereumGrt,
        TokensStore.Token.ethereumPepe,
        
        // AVAX
        TokensStore.Token.avalanche,
        TokensStore.Token.avalancheUsdc,
        TokensStore.Token.avalancheUsdt ,
        TokensStore.Token.avalancheBtc ,
        TokensStore.Token.avalancheSAvax ,
        TokensStore.Token.avalancheJOE ,
        TokensStore.Token.avalanchePNG ,
        TokensStore.Token.avalancheWAVAX ,
        TokensStore.Token.avalancheAAvaUSDC ,
        TokensStore.Token.avalancheBLS ,
        TokensStore.Token.avalancheCOQ ,
        
        // BSC
        TokensStore.Token.bscChainBnb,
        TokensStore.Token.bscChainUsdt,
        TokensStore.Token.bscChainUsdc,
        TokensStore.Token.bscDai,
        TokensStore.Token.bscWeth,
        TokensStore.Token.bscAave,
        TokensStore.Token.bscComp,
        TokensStore.Token.bscSushi,
        TokensStore.Token.bscKnc,
        TokensStore.Token.bscPepe,
        
        // BASE https://basescan.org/tokens
        TokensStore.Token.baseEth,
        TokensStore.Token.baseUsdc,
        TokensStore.Token.baseWewe,
        TokensStore.Token.baseDai,
        TokensStore.Token.baseRETH,
        TokensStore.Token.baseEZETH,
        TokensStore.Token.basePYTH,
        TokensStore.Token.baseOM,
        TokensStore.Token.baseW,
        TokensStore.Token.baseCBETH,
        TokensStore.Token.baseSNX,
        TokensStore.Token.baseAERO,
        
        // ARB https://arbiscan.io/tokens
        TokensStore.Token.arbETH,
        TokensStore.Token.arbArb,
        TokensStore.Token.arbFox,
        TokensStore.Token.arbTGT,
        TokensStore.Token.arbUSDT,
        TokensStore.Token.arbUSDCe,
        TokensStore.Token.arbUSDC,
        TokensStore.Token.arbWBTC,
        TokensStore.Token.arbLINK,
        TokensStore.Token.arbDAI,
        TokensStore.Token.arbUNI,
        TokensStore.Token.arbPEPE,
        TokensStore.Token.arbGRT,
        TokensStore.Token.arbEZETH,
        TokensStore.Token.arbPYTH,
        TokensStore.Token.arbLDO,
        
        // OPTIMUM https://optimistic.etherscan.io/tokens
        TokensStore.Token.optETH,
        TokensStore.Token.optOP,
        TokensStore.Token.optFox,
        TokensStore.Token.optUSDT,
        TokensStore.Token.optUSDCe,
        TokensStore.Token.optUSDC,
        TokensStore.Token.optWBTC,
        TokensStore.Token.optLINK,
        TokensStore.Token.optDAI,
        TokensStore.Token.optEZETH,
        TokensStore.Token.optPYTH,
        TokensStore.Token.optLDO,
        
        // POL
        TokensStore.Token.pol,
        TokensStore.Token.polWETH,
        TokensStore.Token.polFox,
        TokensStore.Token.polUSDT,
        TokensStore.Token.polBNB,
        TokensStore.Token.polSOL,
        TokensStore.Token.polUSDC,
        TokensStore.Token.polUSDCe,
        TokensStore.Token.polBUSD,
        TokensStore.Token.polWBTC,
        TokensStore.Token.polAVAX,
        TokensStore.Token.polSHIB,
        TokensStore.Token.polLINK,
        
        // BLAST
        TokensStore.Token.blastETH,
        TokensStore.Token.blastWETH,
        TokensStore.Token.blastWBTC,
        TokensStore.Token.blastUSDB,
        TokensStore.Token.blastBLAST,
        TokensStore.Token.blastMIM,
        TokensStore.Token.blastBLOOKS,
        TokensStore.Token.blastBAG,
        TokensStore.Token.blastZERO,
        TokensStore.Token.blastAI,
        TokensStore.Token.blastJUICE,
        TokensStore.Token.blastOMNI,
        TokensStore.Token.blastDACKIE,

        // CRONOS
        TokensStore.Token.cronosCRO,
        
        // ZSYNC
        TokensStore.Token.zksyncETH,
        
        // END EVMS
    ]
    
    enum TokenSelectionAssetError: Error {
        case error(message: String)
        
        var localizedDescription: String {
            switch self {
            case let .error(message):
                return "Error: \(message)"
            }
        }
    }
}
