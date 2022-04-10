from brownie import MyContract
from web3 import Web3
from scripts.helpful_scripts import get_accounts


def deploy():
    [deployer] = get_accounts(1)
    mycontracts = MyContract.deploy({"from": deployer})
    print(f"deployed: {mycontracts}")


def main():
    deploy()
