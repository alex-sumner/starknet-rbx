use core::traits::Into;
use core::traits::TryInto;
use super::utils::deploy_contracts;
use starknet::{ContractAddress, EthAddress};
use rabbitx::rabbitx::{IRabbitXDispatcher, IRabbitXDispatcherTrait, RabbitX};
use rabbitx::erc20::{IERC20Dispatcher, IERC20DispatcherTrait}; 
use snforge_std::{declare, cheatcodes::contract_class::ContractClassTrait, spy_events, SpyOn, EventSpy, EventAssertions, start_prank, stop_prank, CheatTarget};

const initial_deposit_id: felt252 = 0x1000000000000000000;
const usdr_owner: felt252 = 0x0059eCeb6748806F3cC446ed0791efc993172eACcdC768f6496c394430c7a337;

const owner: felt252 = 0x123;
const signer: felt252 = 0x62d283FE6939c01FC88f02C6d2C9A547Cc3e2656;

fn set_up() -> (IRabbitXDispatcher, IERC20Dispatcher) {
    let initial_supply: felt252 = 1000000000000000000000;
    let (rabbitx_address, usdr_address) = deploy_contracts(owner, initial_supply, usdr_owner, initial_deposit_id, signer);
    (IRabbitXDispatcher{ contract_address: rabbitx_address }, IERC20Dispatcher{ contract_address: usdr_address })
}

#[test]
fn check_set_token() {
    let (rabbitx, _usdr) = set_up();
    let mut spy = spy_events(SpyOn::One(rabbitx.contract_address));
    let new_token: felt252 = 0x123;
    let new_token_address = new_token.try_into().unwrap();
    let owner_address: ContractAddress = owner.try_into().unwrap();
    start_prank(CheatTarget::One(rabbitx.contract_address), owner_address);
    rabbitx.set_payment_token(new_token_address);
    spy.assert_emitted(@array![
        (
            rabbitx.contract_address,
            RabbitX::Event::SetToken(
                RabbitX::SetToken { token: new_token_address }
            )
        )
    ]);
}

#[should_panic(expected: ('only owner', ))]
#[test]
fn check_only_owner_can_set_token() {
    let (rabbitx, _usdr) = set_up();
    let new_token: felt252 = 0x123;
    let new_token_address = new_token.try_into().unwrap();
    let other_felt: felt252 = 0x456abc;
    let other_address: ContractAddress = other_felt.try_into().unwrap();
    start_prank(CheatTarget::One(rabbitx.contract_address), other_address);
    rabbitx.set_payment_token(new_token_address);
}

#[test]
fn check_set_signer() {
    let (rabbitx, _) = set_up();
    let mut spy = spy_events(SpyOn::One(rabbitx.contract_address));
    let new_signer: felt252 = 0x456;
    let new_signer_address = new_signer.try_into().unwrap();
    let owner_address: ContractAddress = owner.try_into().unwrap();
    start_prank(CheatTarget::One(rabbitx.contract_address), owner_address);
    rabbitx.change_signer(new_signer_address);
    spy.assert_emitted(@array![
        (
            rabbitx.contract_address,
            RabbitX::Event::SetSigner(
                RabbitX::SetSigner { signer: new_signer_address }
            )
        )
    ]);
}

#[should_panic(expected: ('only owner', ))]
#[test]
fn check_only_owner_can_set_signer() {
    let (rabbitx, _usdr) = set_up();
    let new_signer: felt252 = 0x123;
    let new_signer_address = new_signer.try_into().unwrap();
    let other_felt: felt252 = 0x456abc;
    let other_address: ContractAddress = other_felt.try_into().unwrap();
    start_prank(CheatTarget::One(rabbitx.contract_address), other_address);
    rabbitx.change_signer(new_signer_address);
}

#[should_panic(expected: ('ERC20: insufficient allowance', ))]
#[test]
fn check_deposit_without_allowance() {
    let (rabbitx, _) = set_up();
    let trader: felt252 = 0x456;
    let trader_address = trader.try_into().unwrap();
    let amount: u256 = 1234567;
    start_prank(CheatTarget::One(rabbitx.contract_address), trader_address);
    rabbitx.deposit(amount);
}

#[should_panic(expected: ('ERC20: insufficient balance', ))]
#[test]
fn check_deposit_without_balance() {
    let (rabbitx, usdr) = set_up();
    let trader: felt252 = 0x456;
    let trader_address = trader.try_into().unwrap();
    let amount: u256 = 1234567;
    start_prank(CheatTarget::One(usdr.contract_address), trader_address);
    usdr.approve(rabbitx.contract_address, amount);
    stop_prank(CheatTarget::One(usdr.contract_address));
    start_prank(CheatTarget::One(rabbitx.contract_address), trader_address);
    rabbitx.deposit(amount);
}

#[test]
fn check_deposit() {
    let (rabbitx, usdr) = set_up();
    let mut spy = spy_events(SpyOn::One(rabbitx.contract_address));
    let trader: felt252 = 0x456;
    let trader_address = trader.try_into().unwrap();
    let amount: u256 = 1234567;
    let usdr_owner_address: ContractAddress = usdr_owner.try_into().unwrap();
    start_prank(CheatTarget::One(usdr.contract_address), usdr_owner_address);
    usdr.transfer(trader_address, amount);
    stop_prank(CheatTarget::One(usdr.contract_address));
    start_prank(CheatTarget::One(usdr.contract_address), trader_address);
    usdr.approve(rabbitx.contract_address, amount);
    stop_prank(CheatTarget::One(usdr.contract_address));
    start_prank(CheatTarget::One(rabbitx.contract_address), trader_address);
    rabbitx.deposit(amount);
    spy.assert_emitted(@array![
        (
            rabbitx.contract_address,
            RabbitX::Event::Deposit(
                RabbitX::Deposit { id: initial_deposit_id.into(), trader: trader_address, amount: amount }
            )
        )
    ]);
}

#[test]
fn check_withdraw() {
    let (rabbitx, usdr) = set_up();
    let rabbitx_addr_felt: felt252 = rabbitx.contract_address.try_into().unwrap();
    println!("RabbitX address: {}", rabbitx_addr_felt);
    let amount: u256 = 123456000000000000000;
    let usdr_owner_address: ContractAddress = usdr_owner.try_into().unwrap();
    start_prank(CheatTarget::One(usdr.contract_address), usdr_owner_address);
    usdr.transfer(rabbitx.contract_address, amount);
    stop_prank(CheatTarget::One(usdr.contract_address));
    let mut spy = spy_events(SpyOn::One(rabbitx.contract_address));
    let id: u256 = 0x7;
    let trader: felt252 = 0x0376AAc07Ad725E01357B1725B5ceC61aE10473c;
    let trader_address: ContractAddress = trader.try_into().unwrap();
    start_prank(CheatTarget::One(rabbitx.contract_address), trader_address);
    let v: u32 = 27;
    let r: u256 = 0xe8b0d1a429d3fd87a200e4da9347f070a9edd5989edbdcb4eed86734c066380d;
    let s: u256 = 0x0ae23a5897a7d808cc851faadb23c9d14eed1bb4d7ff9d38cfa04f66f70d345e; 
    let trader_balance_before = usdr.balance_of(trader_address);
    let rabbitx_balance_before = usdr.balance_of(rabbitx.contract_address);
    rabbitx.withdraw(id, trader_address, amount, v, r, s);
    let trader_balance_after = usdr.balance_of(trader_address);
    let rabbitx_balance_after = usdr.balance_of(rabbitx.contract_address);
    assert_eq!(trader_balance_after, trader_balance_before + amount);
    assert_eq!(rabbitx_balance_after, rabbitx_balance_before - amount);
    spy.assert_emitted(@array![
        (
            rabbitx.contract_address,
            RabbitX::Event::WithdrawalReceipt (
                RabbitX::WithdrawalReceipt {id: id, trader: trader_address, amount: amount }
            )
        )
    ]);
}

#[should_panic(expected: ('invalid signature', ))]
#[test]
fn check_withdraw_fails_if_amount_changed() {
    let (rabbitx, usdr) = set_up();
    let amount: u256 = 123456000000000000001;
    let usdr_owner_address: ContractAddress = usdr_owner.try_into().unwrap();
    start_prank(CheatTarget::One(usdr.contract_address), usdr_owner_address);
    usdr.transfer(rabbitx.contract_address, amount);
    stop_prank(CheatTarget::One(usdr.contract_address));
    let id: u256 = 0x7;
    let trader: felt252 = 0x0376AAc07Ad725E01357B1725B5ceC61aE10473c;
    let trader_address: ContractAddress = trader.try_into().unwrap();
    start_prank(CheatTarget::One(rabbitx.contract_address), trader_address);
    let v: u32 = 27;
    let r: u256 = 0xe8b0d1a429d3fd87a200e4da9347f070a9edd5989edbdcb4eed86734c066380d;
    let s: u256 = 0x0ae23a5897a7d808cc851faadb23c9d14eed1bb4d7ff9d38cfa04f66f70d345e; 
    rabbitx.withdraw(id, trader_address, amount, v, r, s);
}

#[should_panic(expected: ('invalid signature', ))]
#[test]
fn check_withdraw_fails_if_id_changed() {
    let (rabbitx, usdr) = set_up();
    let amount: u256 = 123456000000000000000;
    let usdr_owner_address: ContractAddress = usdr_owner.try_into().unwrap();
    start_prank(CheatTarget::One(usdr.contract_address), usdr_owner_address);
    usdr.transfer(rabbitx.contract_address, amount);
    stop_prank(CheatTarget::One(usdr.contract_address));
    let id: u256 = 0x8;
    let trader: felt252 = 0x0376AAc07Ad725E01357B1725B5ceC61aE10473c;
    let trader_address: ContractAddress = trader.try_into().unwrap();
    start_prank(CheatTarget::One(rabbitx.contract_address), trader_address);
    let v: u32 = 27;
    let r: u256 = 0xe8b0d1a429d3fd87a200e4da9347f070a9edd5989edbdcb4eed86734c066380d;
    let s: u256 = 0x0ae23a5897a7d808cc851faadb23c9d14eed1bb4d7ff9d38cfa04f66f70d345e; 
    rabbitx.withdraw(id, trader_address, amount, v, r, s);
}

#[should_panic(expected: ('invalid signature', ))]
#[test]
fn check_withdraw_fails_if_withdrawer_changed() {
    let (rabbitx, usdr) = set_up();
    let amount: u256 = 123456000000000000000;
    let usdr_owner_address: ContractAddress = usdr_owner.try_into().unwrap();
    start_prank(CheatTarget::One(usdr.contract_address), usdr_owner_address);
    usdr.transfer(rabbitx.contract_address, amount);
    stop_prank(CheatTarget::One(usdr.contract_address));
    let id: u256 = 0x7;
    let trader: felt252 = 0x0376AAc07Ad725E01357B1725B5ceC61aE10473b;
    let trader_address: ContractAddress = trader.try_into().unwrap();
    start_prank(CheatTarget::One(rabbitx.contract_address), trader_address);
    let v: u32 = 27;
    let r: u256 = 0xe8b0d1a429d3fd87a200e4da9347f070a9edd5989edbdcb4eed86734c066380d;
    let s: u256 = 0x0ae23a5897a7d808cc851faadb23c9d14eed1bb4d7ff9d38cfa04f66f70d345e; 
    rabbitx.withdraw(id, trader_address, amount, v, r, s);
}

#[test]
fn check_withdraw_to() {
    let (rabbitx, usdr) = set_up();
    let amount: u256 = 111111000000000000000;
    let usdr_owner_address: ContractAddress = usdr_owner.try_into().unwrap();
    start_prank(CheatTarget::One(usdr.contract_address), usdr_owner_address);
    usdr.transfer(rabbitx.contract_address, amount);
    stop_prank(CheatTarget::One(usdr.contract_address));
    let mut spy = spy_events(SpyOn::One(rabbitx.contract_address));
    let owner_address: ContractAddress = owner.try_into().unwrap();
    start_prank(CheatTarget::One(rabbitx.contract_address), owner_address);
    let recipient: felt252 = 0x0376A;
    let recipient_address: ContractAddress = recipient.try_into().unwrap();
    let recipient_balance_before = usdr.balance_of(recipient_address);
    let rabbitx_balance_before = usdr.balance_of(rabbitx.contract_address);
    rabbitx.withdraw_tokens_to(amount, recipient_address);
    spy.assert_emitted(@array![
        (
            rabbitx.contract_address,
            RabbitX::Event::WithdrawTo (
                RabbitX::WithdrawTo {to: recipient_address, amount: amount }
            )
        )
    ]);
    let recipient_balance_after = usdr.balance_of(recipient_address);
    let rabbitx_balance_after = usdr.balance_of(rabbitx.contract_address);
    assert_eq!(recipient_balance_after, recipient_balance_before + amount);
    assert_eq!(rabbitx_balance_after, rabbitx_balance_before - amount);
}

#[should_panic(expected: ('only owner', ))]
#[test]
fn check_only_owner_can_withdraw_tokens() {
    let (rabbitx, _usdr) = set_up();
    let recipient: felt252 = 0x123;
    let recipient_address = recipient.try_into().unwrap();
    let other_felt: felt252 = 0x456abc;
    let other_address: ContractAddress = other_felt.try_into().unwrap();
    start_prank(CheatTarget::One(rabbitx.contract_address), other_address);
    rabbitx.withdraw_tokens_to(1, recipient_address);
}
