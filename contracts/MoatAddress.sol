// Implement the proper governance mechanism to update the admin address like admin have rights to upgrade anything but not just "admin". Governance will be used to set admin address.

pragma solidity ^0.4.24;


contract AddressRegistry {

    event AddressChanged(string name, address target);
    mapping(bytes32 => address) internal addressRegistry;

    modifier onlyAdmin() {
        require(
            msg.sender == getAddr("admin"),
            "Permission Denied"
        );
        _;
    }

    constructor() public {
        addressRegistry[keccak256("admin")] = msg.sender;
    }

    function setAddr(string name, address newAddress) public onlyAdmin {
        addressRegistry[keccak256(name)] = newAddress;
        emit AddressChanged(name, newAddress);
    }

    function getAddr(string name) public view returns(address addr) {
        addr = addressRegistry[keccak256(name)];
        require(addr != address(0), "Not a valid address.");
    }

}