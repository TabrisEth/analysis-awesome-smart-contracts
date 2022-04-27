from brownie import Contract, UniswapV2ERC20

from web3 import Web3
import time, sys
from scripts.helpful_scripts import get_accounts


def set_env():
    """
    设置一些环境变量,并且设置为global
    """
    global deployer, account1
    [deployer, account1] = get_accounts(2)
    return


def deploy_token():
    token_contract = UniswapV2ERC20.deploy({"from": deployer})
    print(f"token_contract deployed: {token_contract}")
    return


def main():
    set_env()
    deploy_token()
