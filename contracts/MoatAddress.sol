// addresses name - address, asset, resolver, moatkyber, moatmaker, admin

pragma solidity ^0.4.24;


contract AddressRegistry {

    event AddressChanged(string name, address addr);
    event ResolverApproved(address user, address addr);
    event ResolverDisapproved(address user, address addr);

    // Addresses managing the protocol governance
    mapping(address => bool) public governors;

    // Address registry of connected smart contracts
    mapping(bytes32 => address) public registry;

    // Contract addresses having rights to perform tasks, approved by users
    // Resolver Contract >> User >> Approved
    mapping(address => mapping(address => bool)) public resolvers;

}


contract ManageRegistry is AddressRegistry {

    address public pendingAdmin;
    uint public pendingTime;

    function setPendingAdmin() public {
        require(block.timestamp > pendingTime, "Pending!");
        registry[keccak256("admin")] = pendingAdmin;
    }

    function setAddr(string name, address newAddr) public {
        if (keccak256(name) != keccak256("admin")) {
            require(
                governors[msg.sender],
                "Permission Denied"
            );
            pendingAdmin = newAddr;
            pendingTime = block.timestamp + (24 * 60 * 60); // adding 24 hours
        } else {
            require(
                msg.sender == getAddr("admin"),
                "Permission Denied"
            );
            registry[keccak256(name)] = newAddr;
            emit AddressChanged(name, newAddr);
        }
    }

    function getAddr(string name) public view returns(address addr) {
        addr = registry[keccak256(name)];
        require(addr != address(0), "Not a valid address.");
    }

}


contract ManageResolvers is ManageRegistry {

    function approveResolver() public {
        resolvers[getAddr("resolver")][msg.sender] = true;
        emit ResolverApproved(msg.sender, getAddr("resolver"));
    }

    function disapproveResolver() public {
        resolvers[getAddr("resolver")][msg.sender] = false;
        emit ResolverDisapproved(msg.sender, getAddr("resolver"));
    }

    function isApprovedResolver(address user) public view returns(bool) {
        return resolvers[getAddr("resolver")][user];
    }

}


contract InitRegistry is ManageResolvers {

    constructor() public {
        registry[keccak256("admin")] = msg.sender;
    }

}