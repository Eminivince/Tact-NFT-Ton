import {
    Address,
    beginCell,
    contractAddress,
    toNano,
    TonClient4,
    internal,
    fromNano,
    WalletContractV4,
} from "@ton/ton";
import { mnemonicToPrivateKey } from "@ton/crypto";
import * as dotenv from "dotenv";
dotenv.config();

// Import the contracts
import { NftCollection } from "./output/sample_NftCollection";
import { NftItem } from "./output/sample_NftItem";

(async () => {
    // Create client for testnet sandboxv4 API - alternative endpoint
    const client4 = new TonClient4({
        endpoint: "https://sandbox-v4.tonhubapi.com", // Test-net
    });

    // Parameters for NFTs
    const OFFCHAIN_CONTENT_PREFIX = 0x01;
    const string_first = "https://gnfd-testnet-sp1.bnbchain.org/view/navis-nft/NFTMetadata/"; // Change to the content URL you prepared
    let newContent = beginCell().storeInt(OFFCHAIN_CONTENT_PREFIX, 8).storeStringRefTail(string_first).endCell();

    // Get the wallet mnemonics and derive keys
    let mnemonics = (process.env.mnemonics || "").toString();
    let keyPair = await mnemonicToPrivateKey(mnemonics.split(" "));
    let secretKey = keyPair.secretKey;
    let workchain = 0;
    let wallet = WalletContractV4.create({ workchain, publicKey: keyPair.publicKey });
    let wallet_contract = client4.open(wallet);

    console.log("Wallet address: ", wallet_contract.address);

    // Owner address is the wallet address
    let owner = wallet.address;

    // Initialize the contract with the necessary parameters
    let init = await NftCollection.init(owner, newContent, {
        $$type: "RoyaltyParams",
        numerator: 350n, // 350n = 35%
        denominator: 1000n,
        destination: owner,
    });

    let deployContract = contractAddress(0, init);
    let deployAmount = toNano("0.3");

    // Prepare the message to trigger MintFree
    let packed = beginCell().storeUint(0, 32).storeStringTail("MintFree").endCell();

    // Log deployment details
    let balance: bigint = await wallet_contract.getBalance();
    console.log("Current deployment wallet balance: ", fromNano(balance).toString(), "💎TON");
    console.log("Deploying contract to address: ", deployContract);

    // Send the deployment transaction
    let seqno: number = await wallet_contract.getSeqno();
    await wallet_contract.sendTransfer({
        seqno,
        secretKey,
        messages: [
            internal({
                to: deployContract,
                value: deployAmount,
                init: { code: init.code, data: init.data },
                bounce: true,
                body: packed,
            }),
        ],
    });

    console.log("Contract deployed successfully!");

    // Interact with the deployed contract
    let collection_client = client4.open(NftCollection.fromAddress(deployContract));

    // Get and print the collection data
    let latest_indexId = (await collection_client.getGetCollectionData()).next_item_index;
    console.log("Latest indexID after minting free NFTs: ", latest_indexId.toString());

    for (let i = 0; i < 5; i++) {
        let nft_uri = await collection_client.getGetNftUri(BigInt(i));
        console.log(`The nft_uri for type ${i + 1}: [`, nft_uri.toString(), "]");

        let item_address = await collection_client.getGetNftAddressByIndex(BigInt(i));
        console.log(`Minted NFT Item address ${i + 1}: `, item_address);
    }
})();
