use starknet::{ContractAddress, EthAddress};

#[starknet::interface]
trait IVault<T> {
    fn stake(ref self: T, amount: u256);
    fn addRole(ref self: T, signer: ContractAddress, role: u256);
    fn removeRole(ref self: T, signer: ContractAddress, role: uint256);
    fn add_admin(ref self: T, user: ContractAddress);
    fn remove_admin(ref self: T, user: ContractAddress);
    fn add_trader(ref self: T, user: ContractAddress);
    fn remove_trader(ref self: T, user: ContractAddress);
    fn add_treasurer(ref self: T, user: ContractAddress);
    fn remove_treasurer(ref self: T, user: ContractAddress);
    fn set_owner_is_sole_admin(ref self: T, value: bool);
    fn set_payment_token(ref self: T, _paymentToken: ContractAddress);
    fn set_rabbitx(ref self: T, _rabbitx: ContractAddress);
    fn withdraw_tokens_to(ref self: T, amount: u256, to: ContractAddress);

    fn is_valid_signer(self: @T, signer: ContractAddress, role: u256) -> bool;
    fn is_admin(self: @T, user: ContractAddress) -> bool;
    fn is_trader(self: @T, user: ContractAddress) -> bool;
    fn is_treasurer(self: @T, user: ContractAddress) -> bool;
}

#[starknet::contract]
mod Vault {
    use core::array::ArrayTrait;
    use core::traits::Into;
    use starknet::{ContractAddress, get_caller_address };
    use rabbitx::erc20::{IERC20Dispatcher, IERC20DispatcherTrait}; 
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;

    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        owner: starknet::ContractAddress,
        rabbitx: starknet::ContractAddress,
        payment_token: IERC20Dispatcher,
        owner_is_sole_admin: bool,
        next_stake_id: u256,
        signers: LegacyMap::<(ContactAddress, u256), bool>,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, payment_token_address: ContractAddress, initial_stake_id: u256, signer: EthAddress) {
        self.owner.write(owner);
        self.allowances.write((_owner, ADMIN_ROLE), true);
        self.allowances.write((_owner, TREASURER_ROLE), true);
        self.rabbitx.write(_rabbitx);
        self.payment_token.write(IERC20Dispatcher {contract_address: payment_token_address});
        self.next_stake_id.write(initial_stake_id);
    }

   #[abi(embed_v0)]
    impl VaultImpl of IVault<ContractState> {
        const _MIN_STAKE: u256 = 100000000000000000;

        fn stake(ref self: ContractState, amount: u256) {
            assert(amount >= _MIN_STAKE, 'amount too low');
            let stake_id = PrivateFunctionsTrait::allocate_stake_id(ref self);
            let caller = get_caller_address();
            self.emit(stake {id: stake_id, trader: caller, amount: amount});
            let rabbitx = self.rabbitx.read();
            let success = self.payment_token.read().transfer_from(caller, rabbitx.contract_address, amount);
            assert(success, 'transfer failed');
        }
        
        fn add_role(ref self: T, caller: ContractAddress, role: u256) {
            PrivateFunctionsTrait::only_admin(@self);
            self.callers.write((caller, role), true);
            let caller: ContractAddress = get_caller_address();
            emit AddRole(caller, role, caller);
        }

        fn remove_role(ref self: T, caller: ContractAddress, role: uint256) {
            PrivateFunctionsTrait::only_admin(@self);
            self.callers.write((caller, role), false);
            let caller: ContractAddress = get_caller_address();
            emit RemoveRole(caller, role, caller);
        }

        fn add_admin(ref self: T, user: ContractAddress) {
            add_role(ref self, user, ADMIN_ROLE);
        }

        fn remove_admin(ref self: T, user: ContractAddress) {
            remove_role(ref self, user, ADMIN_ROLE);
        }

        fn add_trader(ref self: T, user: ContractAddress) {
            add_role(ref self, user, TRADER_ROLE);
        }

        fn remove_trader(ref self: T, user: ContractAddress) {
            remove_role(ref self, user, TRADER_ROLE);
        }

        fn add_treasurer(ref self: T, user: ContractAddress) {
            add_role(ref self, user, TREASURER_ROLE);
        }

        fn remove_treasurer(ref self: T, user: ContractAddress) {
            remove_role(ref self, user, TREASURER_ROLE);
        }

        fn set_owner_is_sole_admin(ref self: T, value: bool) {
            self.owner_is_sole_admin.write(value);
        }
        
        fn set_payment_token(ref self: ContractState, new_token: ContractAddress) {
            PrivateFunctionsTrait::only_owner(@self);
            self.emit(SetToken {token: new_token});
            self.payment_token.write(IERC20Dispatcher {contract_address: new_token});
        }

        fn set_rabbitx(ref self: ContractState, new_rabbitx: ContractAddress) {
            PrivateFunctionsTrait::only_owner(@self);
            self.emit(SetRabbitX {token: new_rabbitx});
            self.rabbitx.write(new_rabbitx);
        }

        fn withdraw_tokens_to(ref self: ContractState, amount: u256, to: ContractAddress) {
            PrivateFunctionsTrait::only_owner(@self);
            assert(amount > 0, 'wrong amount');
            self.emit(WithdrawTo {to: to, amount: amount});
            let success = self.payment_token.read().transfer(to, amount);
            assert(success, 'transfer failed');
        }

        fn is_admin(self: @T, user: ContractAddress) -> bool {
            if (self.owner_is_sole_admin.read()) {
                return user == self.owner.read();
            } else {
                return self.signers.read((user, ADMIN_ROLE));
            }
        }

        fn is_valid_signer(self: @T, signer: ContractAddress, role: u256) -> bool {
            return self.signers.read((user, role));
        }

        fn is_trader(self: @T, user: ContractAddress) -> bool {
            return self.signers.read((user, TRADER_ROLE));
        }

        fn is_treasurer(self: @T, user: ContractAddress) -> bool {
            return self.signers.read((user, TREASURER_ROLE));
        }


    }

    #[generate_trait]
    pub impl PrivateFunctions of PrivateFunctionsTrait {
        fn allocate_stake_id(ref self: ContractState) -> u256 {
            let id = self.next_stake_id.read();
            self.next_stake_id.write(id + 1);
            id
        }

        fn only_owner(self: @ContractState) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            assert(caller == owner, 'only owner');
        }

        fn only_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(VaultImpl::is_admin(self, owner), 'only owner');
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
        Stake: Stake,
        WithdrawTo: WithdrawTo,
        WithdrawalReceipt: WithdrawalReceipt,
        SetSigner: SetSigner,
        SetToken: SetToken,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Stake {
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
    struct SetToken {
        #[key]
        token: ContractAddress
    }

    #[derive(AddRole, starknet::Event)]
    struct AddRole {
        #[key]
        user: ContractAddress,
        role: u256,
        caller: ContractAddress
    }

    #[derive(RemoveRole, starknet::Event)]
    struct RemoveRole {
        #[key]
        user: ContractAddress,
        role: u256,
        caller: ContractAddress
    }

}