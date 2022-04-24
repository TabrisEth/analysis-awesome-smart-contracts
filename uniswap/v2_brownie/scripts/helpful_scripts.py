from brownie import accounts, network, config, Contract

FORKED_LOCAL_ENVIRONMENTS = ["mainnet-fork", "mainnet-fork-dev"]
LOCAL_BLOCKCHAIN_ENVIRONMENTS = ["development", "ganache-local"]


def get_accounts(number=1):

    if (
        network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS
        or network.show_active() in FORKED_LOCAL_ENVIRONMENTS
    ):
        result = []
        for num in range(number):
            result.append(accounts[num])
        return result
    else:
        return [accounts.add(config["wallets"]["from_key"])]
