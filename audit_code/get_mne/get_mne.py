# -*- coding: utf-8 -*-
import sys, json
from web3 import Web3
from brownie.convert import to_uint

# from solcx import compile_standard
from solcx import compile_standard, install_solc

w3 = Web3(Web3.HTTPProvider("https://ropsten.infura.io/v3/***"))

chain_id = 3

Decimals = 10**18
EIP20_ABI = json.loads(
    '[{"constant":true,"inputs":[],"name":"name","outputs":[{"name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"name":"_spender","type":"address"},{"name":"_value","type":"uint256"}],"name":"approve","outputs":[{"name":"","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"totalSupply","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"name":"_from","type":"address"},{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transferFrom","outputs":[{"name":"","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[{"name":"_owner","type":"address"},{"name":"_spender","type":"address"}],"name":"allowance","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"anonymous":false,"inputs":[{"indexed":true,"name":"_from","type":"address"},{"indexed":true,"name":"_to","type":"address"},{"indexed":false,"name":"_value","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"_owner","type":"address"},{"indexed":true,"name":"_spender","type":"address"},{"indexed":false,"name":"_value","type":"uint256"}],"name":"Approval","type":"event"}]'
)
# ropsten
contract_addr = "0x6373783401AdD8979ee911E3814485805a86d22F"

# 自己的账号：
account1 = "**"
private_key1 = "***"

# 攻击者的账号：
account2 = "***"
private_key2 = "**"

account2_balance = w3.eth.get_balance(account2)
print(f"account2_balance: {account2_balance}")
# sys.exit(0)

account1_nonce = w3.eth.getTransactionCount(account1)
account2_nonce = w3.eth.getTransactionCount(account2)
print(f"account1_nonce: {account1_nonce}")
print(f"account2_nonce: {account2_nonce}")

gas_price = w3.eth.gas_price
print(f"gas_price: {gas_price}")


def send_ether():
    # sign the transaction
    print("running func.. send_ether: 0.01 ether")
    signed_tx = w3.eth.account.sign_transaction(
        {
            "nonce": account1_nonce,
            "to": account2,
            "value": 10000000000000000,
            "gas": 21000,
            "gasPrice": gas_price + 1,
        },
        private_key1,
    )

    # send transaction
    tx_hash = w3.eth.sendRawTransaction(signed_tx.rawTransaction)
    print(f"calling  func...: {tx_hash.hex()}")
    # w3.eth.wait_for_transaction_receipt(tx_hash)


def send_erc20():
    print("running func.. send_erc20: 1 token")

    token = w3.eth.contract(contract_addr, abi=EIP20_ABI)
    gas_price = int(account2_balance / 37130)
    print(f"account1 erc20 token balance: {token.functions.balanceOf(account2).call()}")
    contract_transaction = token.functions.transfer(
        account1, 1 * Decimals
    ).buildTransaction(
        {
            "chainId": chain_id,
            "gasPrice": gas_price,
            "nonce": account2_nonce,
            "from": account2,
            # "gas": 21000,
        }
    )
    signed_contract_txn = w3.eth.account.sign_transaction(
        contract_transaction, private_key=private_key2
    )
    tx_contract_hash = w3.eth.send_raw_transaction(signed_contract_txn.rawTransaction)
    print(f"calling callsettle func...: {tx_contract_hash.hex()}")
    # tx_receipt = w3.eth.wait_for_transaction_receipt(tx_contract_hash)

    return


def main():
    # send_ether()
    send_erc20()


main()
