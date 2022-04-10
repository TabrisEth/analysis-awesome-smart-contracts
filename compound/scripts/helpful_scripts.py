from cgitb import reset
from brownie import accounts


def get_accounts(number=3):
    result = []
    for num in range(number):
        result.append(accounts[num])
    return result
