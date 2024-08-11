import "./message.tact";
const minTonsForStorage: Int = ton("0.02");
const gasConsumption: Int = ton("0.02");

// nft collection will serve as the parent
// this contract will deploy all individual nfts

/* The role of the collection contract:
1.  Allow any address to mint 6 free nft ships once.
2.  Free NFT ships must be soulbound (feature to be implemented in the child contract).
3.  Collection hold the base data for the metadata.
4.  Allow users to mintpremium NFT by paying the required price.


 */

contract NftCollection {
    next_item_index: Int as uint32 = 0;
    owner_address: Address;
    royalty_params: RoyaltyParams?;                      
    collection_content: Cell;   

    init(owner_address: Address, collection_content: Cell, royalty_params: RoyaltyParams){
        self.owner_address = owner_address;
        self.collection_content = collection_content; 
        self.royalty_params = royalty_params;
    }

    receive("MintFree"){
        let ctx: Context = context(); // get sender Info
        let msgValue: Int = ctx.value;
        // let type: Int = ctx.type;
        let tonBalanceBeforeMsg: Int = myBalance() - msgValue;
        let storageFee: Int = minTonsForStorage - min(tonBalanceBeforeMsg, minTonsForStorage);
        msgValue = msgValue - (storageFee + gasConsumption);

        let i: Int = 0;
        while (i <= 5) {
            i = i + 1;
            self.mintFree(ctx.sender, msgValue, i);
            emit(LogEventMintRecord{ minter: sender(), item_id: self.next_item_index, generate_number: nativeRandom() }.toCell());
         }
    }

    // ===== Private Methods ===== //
    fun mintFree(sender: Address, msgValue: Int, type: Int) {
        //TO-DO: check to make sure, calling address doesnt already own any free nft
        //Loops six times and mints free NFT for caller
        // let i: Int = 0;
        // while (i <= 5) {            // loop while a condition is true
        //     i = i + 1;
            let nft_init: StateInit = self.getNftItemInit(self.next_item_index);
            let collection_content: Cell = self.get_nft_uri(type);
        send(SendParameters{
                to: contractAddress(nft_init), 
                value: msgValue, 
                bounce: false,
                mode: SendIgnoreErrors,
                body: Transfer {
                    query_id: 0,
                    new_owner: sender,
                    response_destination: self.owner_address,
                    custom_payload: collection_content,
                    forward_amount: 0,
                    forward_payload: emptySlice()
                }.toCell(),
                code: nft_init.code,
                data: nft_init.data
            });
            self.next_item_index + 1;
         dump(self.next_item_index);
         dump(self.get_nft_uri(type)); // Reference at: https://tact-by-example.org/03-emit
        //self.next_item_index = self.next_item_index + 1;
        // }
       

       



        
    }

    // fun mintPremium(sender: Address, msgValue: Int, type: Int){
    //     require(type > 5, "Invalid Premuim Type");
    //     //let premiumNFTInit: StateInit = 
    // }

    receive(msg: GetRoyaltyParams) {   
        let ctx: Context = context(); // get sender Info
        send(SendParameters{
            to: ctx.sender,
            value: 0,
            mode: 64, 
            bounce: false,
            body: ReportRoyaltyParams {
                query_id: msg.query_id,
                numerator:  (self.royalty_params!!).numerator,
                denominator: (self.royalty_params!!).denominator,
                destination: self.owner_address
            }.toCell()
        });        
    }

    // ------------------ Get Function  ------------------ //
    get fun get_collection_data(): CollectionData {     
        let b: StringBuilder = beginString();
        let collectionDataString: String = self.collection_content.asSlice().asString();
        b.append(collectionDataString);
        b.append("1.json"); // You can change this your self.
        return CollectionData{
            next_item_index: self.next_item_index, 
            collection_content: b.toCell(), 
            owner_address: self.owner_address
        };
    }

    get fun get_nft_uri(type: Int): Cell{
        let uri: StringBuilder = beginString()
            .concat("https://gnfd-testnet-sp1.bnbchain.org/view/navis-nft/NFTMetadata/")
            .concat(type.toString())
            .concat(".json");
        //let b: Builder = beginCell();
        //let s: Slice = "https://gnfd-testnet-sp1.bnbchain.org/view/navis-nft/NFTMetadata/".asSlice();
        //let t: Slice = type.asSlice();
      let OFFCHAIN_CONTENT_PREFIX: Int = 0x01;
        let newContent: Cell = beginCell().storeInt(OFFCHAIN_CONTENT_PREFIX, 8).storeSlice(uri.toSlice()).endCell();
        return newContent;
    }

    get fun get_nft_address_by_index(item_index: Int): Address?{      
        let initCode: StateInit = self.getNftItemInit(item_index);
        return contractAddress(initCode);
    }
   

    get fun getNftItemInit(item_index: Int): StateInit {
        return initOf NftItem(myAddress(), item_index);
    }
    
    get fun get_nft_content(index: Int, individual_content: Cell): Cell { 
        let b: StringBuilder = beginString();
        let ic: String = individual_content.asSlice().asString();
        b.append(ic);
        return b.toCell();
    }

    get fun royalty_params(): RoyaltyParams {
        return self.royalty_params!!;
    }
}

contract NftItem {
    collection_address: Address;
    item_index: Int; 
    is_initialized: Bool;

    owner: Address?;
    individual_content: Cell?;

    init(collection_address: Address, item_index: Int){
        require(sender() == collection_address, "not from collection");
        self.collection_address = collection_address;
        self.item_index = item_index;
        self.is_initialized = false;
    }

    receive(msg: Transfer){
        let ctx: Context = context(); // Reference: https://docs.tact-lang.org/language/ref/common#context
        let msgValue: Int = self.msgValue(ctx.value);
        
        if (self.is_initialized == false) {  // Initial Transfer, aka the "Minting" of the NFT
            require(ctx.sender == self.collection_address, "initialized tx need from collection");
            self.is_initialized = true;
            self.owner = msg.new_owner;
            self.individual_content = msg.custom_payload;
            send(SendParameters{
                to: msg.response_destination!!,
                value: msgValue,
                mode: SendPayGasSeparately,
                body: Excesses { query_id: msg.query_id }.toCell()
            });
        } else {
            require(ctx.sender == self.owner!!, "not owner");
            self.owner = msg.new_owner;  // change current owner to the new_owner
            if (msg.forward_amount > 0) {
                send(SendParameters{
                    to: msg.new_owner,
                    value: msg.forward_amount,
                    mode:  SendPayGasSeparately, 
                    bounce: true,
                    body: OwnershipAssigned{
                        query_id: msg.query_id,
                        prev_owner: ctx.sender,
                        forward_payload: msg.forward_payload
                    }.toCell()
                }); 
            }

            msgValue = msgValue - ctx.readForwardFee(); 
            if (msg.response_destination != null) { 
                send(SendParameters{ 
                    to: msg.response_destination!!,
                    value: msgValue - msg.forward_amount,
                    mode: SendPayGasSeparately,
                    bounce: true,
                    body: Excesses { query_id: msg.query_id }.toCell()
                });
            } 
        }
    }
    
    receive(msg: GetStaticData){ 
        let ctx: Context = context();
        send(SendParameters {
            to: ctx.sender,
            value: 0,
            mode: 64,  // (return msg amount except gas fees) 
            bounce: true,
            body: ReportStaticData{
                query_id: msg.query_id,
                index_id: self.item_index,
                collection: self.collection_address
            }.toCell()
        });
    }

    fun msgValue(value: Int): Int {
        let tonBalanceBeforeMsg: Int = myBalance() - value;
        let storageFee: Int = minTonsForStorage - min(tonBalanceBeforeMsg, minTonsForStorage);
        return value - (storageFee + gasConsumption);
    }

    // --------- Get Function  --------- //
    get fun get_nft_data(): GetNftData {
        let b: StringBuilder = beginString();
        let collectionData: String = (self.individual_content!!).asSlice().asString();
        b.append(collectionData);
        b.append(self.item_index.toString());
        b.append(".json");

        return GetNftData {
            is_initialized: self.is_initialized, 
            index: self.item_index, 
            collection_address: self.collection_address, 
            owner_address: self.owner!!,
            individual_content: b.toCell()
        };
    }
}
