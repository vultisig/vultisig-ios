const fs = require('fs');
const https = require('https');

const url = 'https://raw.githubusercontent.com/vultisig/commondata/main/tokens/tokens.json';
const outputFile = '../VultisigApp/Stores/TokensStore.swift';

// Swift-compatible chain enum mapping
const chainMap = {
    thorchain: "thorChain",
    mayachain: "mayaChain",
    arbitrum: "arbitrum",
    avalanche: "avalanche",
    base: "base",
    cronoschain: "cronosChain",
    bscchain: "bscChain",
    blast: "blast",
    ethereum: "ethereum",
    optimism: "optimism",
    polygon: "polygon",
    zksync: "zksync",
    bitcoin: "bitcoin",
    bitcoincash: "bitcoinCash",
    litecoin: "litecoin",
    dogecoin: "dogecoin",
    dash: "dash",
    gaiachain: "gaiaChain",
    kujira: "kujira",
    dydx: "dydx",
    osmosis: "osmosis",
    terra: "terra",
    terraclassic: "terraClassic",
    noble: "noble",
    akash: "akash",
    ripple: "ripple",
    tron: "tron",
    sui: "sui",
    solana: "solana",
    polkadot: "polkadot",
    ton: "ton",
};

https.get(url, res => {
    let data = '';

    if (res.statusCode !== 200) {
        console.error(`❌ Failed to fetch data. Status: ${res.statusCode}`);
        return;
    }

    res.on('data', chunk => {
        data += chunk;
    });

    res.on('end', () => {
        const jsonData = JSON.parse(data);

        let out = '';
        out += 'import Foundation\n\n';
        out += 'class TokensStore {\n\n';
        out += '    static let TokenSelectionAssets = [\n';

        for (const [chainRaw, tokens] of Object.entries(jsonData)) {
            const chainKey = chainRaw.toLowerCase();
            const chainSwift = chainMap[chainKey];
            if (!chainSwift) {
                console.warn(`⚠️ Unknown chain: ${chainRaw}`);
                continue;
            }

            for (const token of tokens) {
                out += '        CoinMeta(\n';
                out += `            chain: .${chainSwift},\n`;
                out += `            ticker: "${token.ticker}",\n`;
                out += `            logo: "${token.logo}",\n`;
                out += `            decimals: ${token.decimals},\n`;
                out += `            priceProviderId: "${token.price_provider_id || ""}",\n`;
                out += `            contractAddress: "${token.contract_address || ""}",\n`;
                out += `            isNativeToken: ${token.is_native_token}\n`;
                out += '        ),\n';
            }
        }

        out += '    ]\n';
        out += '}\n';

        fs.writeFileSync(outputFile, out);
        console.log('✅ TokensStore.swift generated!');
    });
}).on('error', err => {
    console.error('❌ Error fetching JSON:', err.message);
});