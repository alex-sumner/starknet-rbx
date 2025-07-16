use starknet::{ContractAddress, EthAddress};

const WITHDRAWAL_TYPEHASH: u256 =   0xec976281d6462ad970e7a9251148e624b8aa376c6857d4245700b1b711bb0884;
const EIP712_DOMAIN_TYPEHASH: u256 =  0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
const DOMAIN_NAME_HASH: u256 = 0xd3559b726730ea373e6098c815101d15b46ed934939fa5d5a1b37101196b0538;
const VERSION_HASH: u256 = 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6;

#[starknet::interface]
trait IRabbitX<T> {
    fn withdraw(ref self: T, id: u256, trader: ContractAddress, amount: u256, v: u32, r: u256, s: u256);
    fn deposit(ref self: T, amount: u256);
    fn withdraw_tokens_to(ref self: T, amount: u256, to: ContractAddress);
    fn set_payment_token(ref self: T, new_token: ContractAddress);
    fn change_signer(ref self: T, new_signer: EthAddress);
}

#[starknet::contract]
mod RabbitX {
    use core::array::ArrayTrait;
    use core::traits::Into;
    use starknet::{
        ClassHash, ContractAddress, EthAddress, get_caller_address, get_contract_address, get_tx_info,
        secp256_trait::{
            Secp256Trait, Secp256PointTrait, recover_public_key, is_signature_entry_valid, Signature, signature_from_vrs
        },
        secp256k1::Secp256k1Point,
        eth_signature::public_key_point_to_eth_address
    };
    use alexandria_bytes::bytes::{Bytes, BytesTrait};
    use rabbitx::erc20::{IERC20Dispatcher, IERC20DispatcherTrait}; 
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use super::IRabbitX;

    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        reentry_lock: bool,
        owner: starknet::ContractAddress,
        payment_token: IERC20Dispatcher,
        signer: EthAddress,
        processed_withdrawals: LegacyMap::<u256, bool>,
        next_deposit_id: u256,
        domain_separator: u256,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, payment_token_address: ContractAddress, initial_deposit_id: u256, signer: EthAddress) {
        self.owner.write(owner);
        self.payment_token.write(IERC20Dispatcher {contract_address: payment_token_address});
        self.next_deposit_id.write(initial_deposit_id);
        self.signer.write(signer);

        // make the eip712 domain separator from the EIP712_DOMAIN_TYPEHASH, DOMAIN_NAME_HASH, 
        // VERSION_HASH, the chain id and the contract address
        let mut bytes: Bytes = BytesTrait::new(0, array![]);
        bytes.append_u256(super::EIP712_DOMAIN_TYPEHASH);
        bytes.append_u256(super::DOMAIN_NAME_HASH);
        bytes.append_u256(super::VERSION_HASH);
        bytes.append_u256(get_tx_info().unbox().chain_id.into());
        bytes.append_address(get_contract_address());
        self.domain_separator.write(bytes.keccak());
    }

   #[abi(embed_v0)]
    impl RabbitXImpl of IRabbitX<ContractState> {

        fn deposit(ref self: ContractState, amount: u256) {
            let deposit_id = PrivateFunctionsTrait::allocate_deposit_id(ref self);
            let caller = get_caller_address();
            self.emit(Deposit {id: deposit_id, trader: caller, amount: amount});
            let this_address = get_contract_address();
            let success = self.payment_token.read().transfer_from(caller, this_address, amount);
            assert(success, 'transfer failed');
        }
        
        fn withdraw(ref self: ContractState, id: u256, trader: ContractAddress, amount: u256, v: u32, r: u256, s: u256) {
            assert(amount > 0, 'wrong amount');
            let already_processed = self.processed_withdrawals.read(id);
            assert(!already_processed, 'already processed');
            self.processed_withdrawals.write(id, true);

            let digest = PrivateFunctionsTrait::get_digest(
                id,
                trader,
                amount,
                self.domain_separator.read()
            );
            let expected_signer = self.signer.read();
            let signature_ok = PrivateFunctionsTrait::verify_signer(
                digest,
                v,
                r,
                s,
                expected_signer
            );
            if !signature_ok {
                core::panic_with_felt252('invalid signature');
            }

            self.emit(WithdrawalReceipt {id: id, trader: trader, amount: amount});
            let success = self.payment_token.read().transfer(trader, amount);
            assert(success, 'transfer failed');
        }

        fn withdraw_tokens_to(ref self: ContractState, amount: u256, to: ContractAddress) {
            PrivateFunctionsTrait::only_owner(@self);
            assert(amount > 0, 'wrong amount');
            self.emit(WithdrawTo {to: to, amount: amount});
            let success = self.payment_token.read().transfer(to, amount);
            assert(success, 'transfer failed');
        }

        fn set_payment_token(ref self: ContractState, new_token: ContractAddress) {
            PrivateFunctionsTrait::only_owner(@self);
            self.emit(SetToken {token: new_token});
            self.payment_token.write(IERC20Dispatcher {contract_address: new_token});
        }

        fn change_signer(ref self: ContractState, new_signer: EthAddress) {
            PrivateFunctionsTrait::only_owner(@self);
            self.emit(SetSigner {signer: new_signer});
            self.signer.write(new_signer);
        }
    }

    #[generate_trait]
    pub impl PrivateFunctions of PrivateFunctionsTrait {
        fn allocate_deposit_id(ref self: ContractState) -> u256 {
            let id = self.next_deposit_id.read();
            self.next_deposit_id.write(id + 1);
            id
        }

        fn get_digest(id: u256, trader: ContractAddress, amount: u256, domain_separator: u256) -> u256 {

            // make struct_hash from WITHDRAWAL_TYPEHASH, id, trader, amount
            let mut bytes: Bytes = BytesTrait::new(0, array![]);
            bytes.append_u256(super::WITHDRAWAL_TYPEHASH);
            bytes.append_u256(id);
            bytes.append_address(trader);
            bytes.append_u256(amount);
            let struct_hash = bytes.keccak();

            // then return the digest from "\x19\x01", the domain separator and struct_hash
            let mut bytes: Bytes = BytesTrait::new(0, array![]);
            bytes.append_u16(0x1901);
            bytes.append_u256(domain_separator);
            bytes.append_u256(struct_hash);
            bytes.keccak()
        }
        
        fn verify_signer(digest: u256, v: u32, r: u256, s: u256, expected_signer: EthAddress) -> bool{
            let signature: Signature = signature_from_vrs(v, r, s);
            if !is_signature_entry_valid::<Secp256k1Point>(signature.r) {
                core::panic_with_felt252('Signature out of range');
            }
            if !is_signature_entry_valid::<Secp256k1Point>(signature.s) {
                core::panic_with_felt252('Signature out of range');
            }
           let public_key_point = recover_public_key::<Secp256k1Point>(msg_hash: digest, :signature).unwrap();
            let calculated_eth_address = public_key_point_to_eth_address(:public_key_point);
            let mut signature_matches = expected_signer == calculated_eth_address;
            if !signature_matches {
                let mut v2: u32 = 27;
                if v == 27 {
                    v2 = 28;
                }
                let signature: Signature = signature_from_vrs(v2, r, s);
                let public_key_point = recover_public_key::<Secp256k1Point>(msg_hash: digest, :signature).unwrap();
                let calculated_eth_address = public_key_point_to_eth_address(:public_key_point);
                signature_matches = expected_signer == calculated_eth_address;
            }
            signature_matches
        }

        fn only_owner(self: @ContractState) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            assert(caller == owner, 'only owner');
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            PrivateFunctionsTrait::only_owner(@self);
            self.upgradeable._upgrade(new_class_hash);
        }
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        WithdrawTo: WithdrawTo,
        WithdrawalReceipt: WithdrawalReceipt,
        SetSigner: SetSigner,
        SetToken: SetToken,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        #[key]
        id: u256,
        #[key]
        trader: ContractAddress,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct WithdrawTo {
        #[key]
        to: ContractAddress,
        amount: u256 
    }

    #[derive(Drop, starknet::Event)]
    struct WithdrawalReceipt {
        #[key]
        id: u256,
        #[key]
        trader: ContractAddress,
        amount: u256 
    }

    #[derive(Drop, starknet::Event)]
    struct SetToken {
        #[key]
        token: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct SetSigner {
        #[key]
        signer: EthAddress
    }

}