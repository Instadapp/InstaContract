pragma solidity ^0.4.24;

interface token {
    function transfer(address receiver, uint amount) external returns (bool);
}

interface AddressRegistry {
    function getAddr(string name) external returns(address);
}


contract Registry {

    address public registryAddress;
    modifier onlyAdmin() {
        require(
            msg.sender == getAddress("admin"),
            "Permission Denied"
        );
        _;
    }

    function getAddress(string name) internal view returns(address addr) {
        AddressRegistry aRegistry = AddressRegistry(registryAddress);
        addr = aRegistry.getAddr(name);
        require(addr != address(0), "Invalid Address");
    }
 
}


contract FeeDetail is Registry {

    uint public fees;
    bool public feeBool;

    function getFees() public view returns(uint, bool) {
        return (fees, feeBool);
    }

    function enableFees() public onlyAdmin {
        feeBool = true;
    }

    function disableFees() public onlyAdmin {
        feeBool = false;
    }

}


contract MoatResolver is FeeDetail {

    function () public payable {}

    constructor(address rAddr, uint cut) public { // 200 means 0.5% 
        registryAddress = rAddr;
        fees = cut;
    }

    function collectFees(address tokenAddress, uint amount) public onlyAdmin {
        if (tokenAddress == 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee) {
            msg.sender.transfer(amount);
        } else {
            token tokenFunctions = token(tokenAddress);
            tokenFunctions.transfer(msg.sender, amount);
        }
    }

}