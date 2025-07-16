use starknet::{ContractAddress};
use snforge_std::{declare, cheatcodes::contract_class::ContractClassTrait};

fn deploy_contracts(owner: felt252, initial_supply: felt252, token_recipient: felt252, initial_deposit_id: felt252, signer: felt252) -> (ContractAddress, ContractAddress) {

    let usdr = declare("USDR");
    let mut constructor_args = ArrayTrait::<felt252>::new();
    constructor_args.append(initial_supply);
    constructor_args.append(0);
    constructor_args.append(token_recipient);
    let usdr_address = usdr.deploy(@constructor_args).unwrap();
    let rabbitx = declare("RabbitX");
    constructor_args = array![owner, usdr_address.into(), initial_deposit_id.into(), 0, signer];
    let rabbitx_address = rabbitx.deploy(@constructor_args).unwrap();
    return (rabbitx_address, usdr_address);
}